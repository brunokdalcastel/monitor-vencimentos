variable "location" {
  description = "Região do Azure (D5: Brazil South)."
  type        = string
  default     = "brazilsouth"
}

variable "resource_group_name" {
  description = "Resource Group de workload (criado pelo infra/bootstrap; referenciado aqui como já existente)."
  type        = string
  default     = "rg-mvenc-dev"
}

variable "environment" {
  description = "Nome do ambiente — usado em nomes de recursos e tags."
  type        = string
  default     = "dev"
}

variable "powershell_version" {
  description = "Versão do worker PowerShell da Function App (ver ADR 0014 — D4 revisada: 7.6, não 7.4)."
  type        = string
  default     = "7.6"
}

variable "admin_email" {
  description = "E-mail do admin que recebe o resumo diário (vira o app setting ADMIN_EMAIL)."
  type        = string
}

variable "daily_log_quota_gb" {
  description = "Limite diário de ingestão do Log Analytics / Application Insights, em GB (mantém dentro do tier sempre gratuito de 5GB/mês em uso esporádico)."
  type        = number
  default     = 1
}

variable "budget_amount" {
  description = "Valor mensal do budget do Resource Group de dev, em BRL."
  type        = number
  default     = 20
}

variable "budget_contact_emails" {
  description = "E-mails que recebem o alerta de budget do Resource Group."
  type        = list(string)
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default = {
    projeto    = "monitor-vencimentos"
    gerenciado = "terraform"
  }
}
