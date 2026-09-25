# ACS Email com domínio gerenciado pelo Azure (D1/D13) — sem custo de domínio, sem
# precisar comprar nada. O Azure atribui um subdomínio tipo "<id>.azurecomm.net" e o
# remetente vira "DoNotReply@<esse-subdominio>".
resource "azurerm_communication_service" "main" {
  name                = "cs-mvenc-${var.environment}"
  resource_group_name = data.azurerm_resource_group.dev.name
  data_location       = "Brazil"
  tags                = var.tags
}

resource "azurerm_email_communication_service" "main" {
  name                = "ecs-mvenc-${var.environment}"
  resource_group_name = data.azurerm_resource_group.dev.name
  data_location       = "Brazil"
  tags                = var.tags
}

# "AzureManagedDomain" é o nome fixo esperado pelo provider para domain_management =
# "AzureManaged" (não é um nome livre) — confirmado contra a API real no primeiro
# apply (T12).
resource "azurerm_email_communication_service_domain" "managed" {
  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.main.id
  domain_management = "AzureManaged"
}

# Sem recurso próprio pro sender username "DoNotReply": o Azure já cria um
# automaticamente junto do domínio gerenciado (descoberto no primeiro apply — a
# criação explícita falhou com "already exists"). Não precisa gerenciar via Terraform.

resource "azurerm_communication_service_email_domain_association" "main" {
  communication_service_id = azurerm_communication_service.main.id
  email_service_domain_id  = azurerm_email_communication_service_domain.managed.id
}
