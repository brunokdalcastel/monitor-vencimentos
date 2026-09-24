location            = "brazilsouth"
resource_group_name = "rg-mvenc-dev"
environment         = "dev"
powershell_version  = "7.6"

admin_email = "voce@exemplo.com"

daily_log_quota_gb = 1

budget_amount         = 20
budget_contact_emails = ["voce@exemplo.com"]

tags = {
  projeto    = "monitor-vencimentos"
  gerenciado = "terraform"
  ambiente   = "dev"
}
