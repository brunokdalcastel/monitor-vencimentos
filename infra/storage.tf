# Table Storage — wrapper REST próprio (D2), sem chave de acesso (D3): a Function
# autentica com a própria identidade gerenciada, mesmo em dev.
resource "azurerm_storage_account" "main" {
  name                       = "stmvenc${var.environment}${random_string.suffix.result}"
  resource_group_name        = data.azurerm_resource_group.dev.name
  location                   = data.azurerm_resource_group.dev.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  shared_access_key_enabled  = false
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
  tags                       = var.tags
}

resource "azurerm_storage_table" "itens" {
  name               = "Itens"
  storage_account_id = azurerm_storage_account.main.id
}

resource "azurerm_storage_table" "verificacoes" {
  name               = "Verificacoes"
  storage_account_id = azurerm_storage_account.main.id
}

resource "azurerm_storage_table" "alertas_enviados" {
  name               = "AlertasEnviados"
  storage_account_id = azurerm_storage_account.main.id
}

resource "azurerm_storage_table" "clientes" {
  name               = "Clientes"
  storage_account_id = azurerm_storage_account.main.id
}

# Container de deploy do pacote da Function (Flex Consumption exige blob container
# próprio, distinto do AzureWebJobsStorage clássico).
resource "azurerm_storage_container" "deploy_package" {
  name                  = "deploy-package"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}
