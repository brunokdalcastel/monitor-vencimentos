# Flex Consumption (D4/ADR 0014): paga só pelo que executa, R$0 parada — é o ponto
# central de rodar isso "de graça, sob demanda" (D13).
resource "azurerm_service_plan" "main" {
  name                = "asp-mvenc-${var.environment}"
  resource_group_name = data.azurerm_resource_group.dev.name
  location            = data.azurerm_resource_group.dev.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = var.tags
}

resource "azurerm_function_app_flex_consumption" "main" {
  name                = "func-mvenc-${var.environment}"
  resource_group_name = data.azurerm_resource_group.dev.name
  location            = data.azurerm_resource_group.dev.location
  service_plan_id     = azurerm_service_plan.main.id

  # SystemAssignedIdentity: nem o storage de deploy usa chave (D3).
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.deploy_package.name}"
  storage_authentication_type = "SystemAssignedIdentity"

  runtime_name    = "powershell"
  runtime_version = var.powershell_version

  instance_memory_in_mb  = 2048
  maximum_instance_count = 40

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    TABELAS_ENDPOINT  = azurerm_storage_account.main.primary_table_endpoint
    TABELAS_MODO_AUTH = "ManagedIdentity"
    EMAIL_MODO        = "Envio"
    ACS_ENDPOINT      = "https://${azurerm_communication_service.main.hostname}"
    # DoNotReply@<domínio gerenciado pelo Azure> — ver observação em email.tf sobre o
    # atributo from_sender_domain não estar confirmado contra a API real ainda.
    ACS_REMETENTE = "DoNotReply@${azurerm_email_communication_service_domain.managed.from_sender_domain}"
    ADMIN_EMAIL   = var.admin_email
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }

  tags = var.tags
}

# --- Papéis da identidade gerenciada da Function — só o necessário (D3) ---

resource "azurerm_role_assignment" "function_table_data" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.main.identity[0].principal_id
}

# Exigido pelo Flex Consumption pra acessar o próprio pacote de deploy via identidade
# (storage_authentication_type = SystemAssignedIdentity, acima).
resource "azurerm_role_assignment" "function_blob_deploy" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_function_app_flex_consumption.main.identity[0].principal_id
}

# Único papel embutido do Azure pra Communication/Email Services — não existe uma
# versão mais restrita "só enviar" (checado com `az role definition list` antes de
# codar). Ver Pendências da T09 sobre essa limitação.
resource "azurerm_role_assignment" "function_acs_send" {
  scope                = azurerm_communication_service.main.id
  role_definition_name = "Communication and Email Service Owner"
  principal_id         = azurerm_function_app_flex_consumption.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_keyvault_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_function_app_flex_consumption.main.identity[0].principal_id
}
