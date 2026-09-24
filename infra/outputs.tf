output "function_app_name" {
  description = "Nome da Function App — usar no deploy (T10) e para consultar logs."
  value       = azurerm_function_app_flex_consumption.main.name
}

output "function_app_default_hostname" {
  value = azurerm_function_app_flex_consumption.main.default_hostname
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "deploy_package_container_url" {
  description = "Container de deploy do pacote da Function (Flex Consumption)."
  value       = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.deploy_package.name}"
}

output "communication_service_hostname" {
  value = azurerm_communication_service.main.hostname
}

output "acs_sender_address" {
  description = "Endereço de remetente do ACS (ACS_REMETENTE) — confirmar contra o valor real após o apply (ver Pendências da T09)."
  value       = "DoNotReply@${azurerm_email_communication_service_domain.managed.from_sender_domain}"
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.main.connection_string
  sensitive = true
}
