# Resource Group de workload — criado no infra/bootstrap (não aqui), pra permitir dar
# Contributor pro GitHub Actions só nesse RG, não na assinatura inteira.
data "azurerm_resource_group" "dev" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

# Sufixo pra nomes que precisam ser globalmente únicos (Storage Account, Key Vault).
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}
