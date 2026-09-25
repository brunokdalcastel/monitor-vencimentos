location            = "brazilsouth"
resource_group_name = "rg-mvenc-dev"
environment         = "dev"
powershell_version  = "7.6"

# admin_email e budget_contact_emails (dados pessoais) NÃO ficam aqui — ver
# infra/pessoal.auto.tfvars.example (local, fora do Git) ou TF_VAR_* no CI.

daily_log_quota_gb = 1

budget_amount = 20

tags = {
  projeto    = "monitor-vencimentos"
  gerenciado = "terraform"
  ambiente   = "dev"
}
