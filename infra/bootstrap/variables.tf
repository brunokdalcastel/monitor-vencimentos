variable "location" {
  description = "Região do Azure para os recursos de bootstrap e para o Resource Group de dev (D5)."
  type        = string
  default     = "brazilsouth"
}

variable "tfstate_resource_group_name" {
  description = "Nome do Resource Group que guarda o Storage Account do state do Terraform."
  type        = string
  default     = "rg-mvenc-tfstate"
}

variable "tfstate_storage_account_name" {
  description = "Nome do Storage Account do state do Terraform. Globalmente único em todo o Azure — se já estiver em uso, ajuste aqui (e no backend.tf da infra/ principal, que precisa apontar pro mesmo nome)."
  type        = string
  default     = "stmvenctfstate"
}

variable "tfstate_container_name" {
  description = "Nome do container de blob onde fica o arquivo de state."
  type        = string
  default     = "tfstate"
}

variable "dev_resource_group_name" {
  description = "Nome do Resource Group de workload do ambiente dev — criado aqui (vazio) para a identidade do GitHub Actions já nascer com permissão só nele; a infra/ principal referencia como Resource Group existente."
  type        = string
  default     = "rg-mvenc-dev"
}

variable "github_repository" {
  description = "Repositório do GitHub no formato owner/repo, usado nas credenciais federadas (OIDC)."
  type        = string
  default     = "brunokdalcastel/monitor-vencimentos"
}

variable "github_environment_name" {
  description = "Nome do GitHub Environment usado pelo workflow de deploy (aprovação manual, ver T10)."
  type        = string
  default     = "dev"
}
