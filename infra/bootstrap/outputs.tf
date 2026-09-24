output "github_actions_client_id" {
  description = "AZURE_CLIENT_ID — variável do repositório GitHub (ver T10)."
  value       = azuread_application.github_actions.client_id
}

output "azure_tenant_id" {
  description = "AZURE_TENANT_ID — variável do repositório GitHub (ver T10)."
  value       = data.azurerm_client_config.current.tenant_id
}

output "azure_subscription_id" {
  description = "AZURE_SUBSCRIPTION_ID — variável do repositório GitHub (ver T10)."
  value       = data.azurerm_client_config.current.subscription_id
}

output "tfstate_resource_group_name" {
  description = "Usar no backend.tf da infra/ principal."
  value       = azurerm_resource_group.tfstate.name
}

output "tfstate_storage_account_name" {
  description = "Usar no backend.tf da infra/ principal."
  value       = azurerm_storage_account.tfstate.name
}

output "tfstate_container_name" {
  description = "Usar no backend.tf da infra/ principal."
  value       = azurerm_storage_container.tfstate.name
}

output "dev_resource_group_name" {
  description = "Usar em environments/dev.tfvars (resource_group_name) da infra/ principal."
  value       = azurerm_resource_group.dev.name
}
