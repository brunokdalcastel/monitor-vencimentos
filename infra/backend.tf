# Backend não aceita variáveis — os valores aqui precisam bater com as saídas do
# infra/bootstrap (tfstate_resource_group_name, tfstate_storage_account_name,
# tfstate_container_name). Se você mudou o nome do Storage Account no bootstrap
# (porque o padrão já estava em uso — nomes de Storage Account são globalmente
# únicos), ajuste aqui também.
# use_azuread_auth: sem chave de acesso (D3) — autentica com a mesma identidade
# (Azure AD) de quem roda o terraform (usuário local via `az login`, ou a identidade
# OIDC do GitHub Actions).
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-mvenc-tfstate"
    storage_account_name = "stmvenctfstate"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
    use_azuread_auth     = true
  }
}
