# Log Analytics + Application Insights com limite diário de ingestão — mantém dentro do
# tier sempre gratuito (5GB/mês) nesse volume de uso (D13: uso pessoal/esporádico).
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-mvenc-${var.environment}"
  resource_group_name = data.azurerm_resource_group.dev.name
  location            = data.azurerm_resource_group.dev.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.daily_log_quota_gb
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                 = "appi-mvenc-${var.environment}"
  resource_group_name  = data.azurerm_resource_group.dev.name
  location             = data.azurerm_resource_group.dev.location
  application_type     = "web"
  workspace_id         = azurerm_log_analytics_workspace.main.id
  daily_data_cap_in_gb = var.daily_log_quota_gb
  tags                 = var.tags
}
