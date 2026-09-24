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
# "AzureManaged" (não é um nome livre) — não confirmado contra a API real ainda (sem
# domínio criado até o primeiro apply); se o apply rejeitar esse nome, ver Pendências
# da T09 no PLANO.md.
resource "azurerm_email_communication_service_domain" "managed" {
  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.main.id
  domain_management = "AzureManaged"
}

resource "azurerm_email_communication_service_domain_sender_username" "nao_responder" {
  email_service_domain_id = azurerm_email_communication_service_domain.managed.id
  name                    = "DoNotReply"
  display_name            = "Monitor de Vencimentos"
}

resource "azurerm_communication_service_email_domain_association" "main" {
  communication_service_id = azurerm_communication_service.main.id
  email_service_domain_id  = azurerm_email_communication_service_domain.managed.id
}
