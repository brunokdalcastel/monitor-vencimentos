# Bootstrap — executado UMA VEZ, manualmente, pelo humano (ver README.md e T09 no
# PLANO.md). Cria o essencial pra tudo o resto (infra/ principal + GitHub Actions)
# funcionar: onde fica o state do Terraform e a identidade OIDC que a esteira usa.
# Depois disso, o resto (infra/) pode ser aplicado via pipeline.

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "tfstate" {
  name     = var.tfstate_resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "tfstate" {
  name                       = var.tfstate_storage_account_name
  resource_group_name        = azurerm_resource_group.tfstate.name
  location                   = azurerm_resource_group.tfstate.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  shared_access_key_enabled  = false # D3: sem chave — auth do backend via Azure AD (use_azuread_auth)
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"
}

resource "azurerm_storage_container" "tfstate" {
  name                  = var.tfstate_container_name
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# RG de workload do dev, criado vazio aqui — a infra/ principal só referencia (data
# source), nunca cria/destrói o Resource Group em si. Isso permite dar Contributor pro
# GitHub Actions só nesse RG (não na assinatura inteira).
resource "azurerm_resource_group" "dev" {
  name     = var.dev_resource_group_name
  location = var.location
}

# --- Identidade OIDC do GitHub Actions (sem segredo — ver ADR 0011/D11) ---

resource "azuread_application" "github_actions" {
  display_name = "monitor-vencimentos-github-actions"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

# Credencial federada para o GitHub Environment "dev" — é o que o workflow de deploy
# (T10, aprovação manual) usa pra logar sem segredo.
resource "azuread_application_federated_identity_credential" "deploy_environment" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-environment-${var.github_environment_name}"
  description    = "Deploy via GitHub Environment '${var.github_environment_name}' (aprovação manual) — ver T10."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:environment:${var.github_environment_name}"
}

# Credencial federada para PRs (workflow de CI: lint, testes, terraform validate) — ver T10.
resource "azuread_application_federated_identity_credential" "pull_request" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-pull-request"
  description    = "CI em pull requests (lint/testes/terraform validate) — ver T10."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:pull_request"
}

# --- Papéis mínimos da identidade, escopados só ao que ela precisa tocar ---

# Cria/gerencia os recursos do workload — só no RG de dev, não na assinatura.
resource "azurerm_role_assignment" "github_actions_contributor_dev" {
  scope                = azurerm_resource_group.dev.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# A infra/ principal atribui papéis à identidade gerenciada da Function (Storage Table
# Data Contributor, Key Vault Secrets User, etc.) — só quem administra RBAC no escopo
# consegue fazer isso. "RBAC Administrator" (e não "User Access Administrator") porque
# esse não permite a identidade se autoelevar pra Owner.
resource "azurerm_role_assignment" "github_actions_rbac_admin_dev" {
  scope                = azurerm_resource_group.dev.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# Ler/gravar o state do Terraform (sem chave — Storage Blob Data Contributor + Azure AD).
resource "azurerm_role_assignment" "github_actions_state_storage" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# Quem roda o bootstrap (e depois a infra/ principal) localmente também precisa disso —
# "Owner"/"Contributor" da assinatura NÃO bastam: são papéis só de controle
# (`dataActions` vazio), sem acesso de dado ao blob do state. Descoberto na prática no
# primeiro apply real (ver Pendências da T12 no PLANO.md) quando o `terraform init` da
# infra/ principal falhou com 403 mesmo sendo Owner da assinatura.
resource "azurerm_role_assignment" "operador_state_storage" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
