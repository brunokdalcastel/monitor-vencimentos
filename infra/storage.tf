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

# As tabelas (Itens, Verificacoes, AlertasEnviados, Clientes) NÃO são gerenciadas aqui
# de propósito — descoberto no primeiro apply real (ver Pendências da T12 no
# PLANO.md): o `azurerm_storage_table` sempre tenta ler/gravar a ACL (stored access
# policy) da tabela em toda operação, e essa API específica do Table Storage nunca
# suportou Azure AD (só chave) — incompatível com `shared_access_key_enabled = false`
# (D3), sem contorno no lado do Terraform. `New-TabelaSeNaoExistir` (módulo Storage,
# T05) já cria as tabelas via REST puro com Managed Identity, sem essa limitação
# (criar tabela é uma operação diferente de gerenciar ACL) — é chamado no início de
# toda execução de `Invoke-VerificacaoDiaria` (T07) e por `tools/Import-Itens.ps1`.

# Container de deploy do pacote da Function (Flex Consumption exige blob container
# próprio, distinto do AzureWebJobsStorage clássico).
resource "azurerm_storage_container" "deploy_package" {
  name                  = "deploy-package"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}
