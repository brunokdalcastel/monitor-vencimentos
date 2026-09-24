# Provisionado conforme pedido pela T09; nenhum módulo hoje lê segredos daqui (o
# projeto todo é sem-segredo — Managed Identity em tudo, ver D2/D3). Reservado pra uso
# futuro (ex.: se algum dia precisar de uma credencial que não dá pra evitar).
resource "azurerm_key_vault" "main" {
  name                       = "kv-mvenc-${random_string.suffix.result}"
  resource_group_name        = data.azurerm_resource_group.dev.name
  location                   = data.azurerm_resource_group.dev.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # dev: permite destruir/recriar sem esperar retenção
  tags                       = var.tags
}
