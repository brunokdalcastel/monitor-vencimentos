# Budget do RG (além do budget de assinatura já configurado manualmente na M0.2) —
# granularidade menor, só pros recursos deste projeto.
resource "azurerm_consumption_budget_resource_group" "main" {
  name              = "budget-mvenc-${var.environment}"
  resource_group_id = data.azurerm_resource_group.dev.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 50
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 80
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    operator       = "GreaterThan"
    threshold      = 100
    contact_emails = var.budget_contact_emails
  }

  lifecycle {
    ignore_changes = [time_period[0].start_date]
  }
}

resource "azurerm_monitor_action_group" "main" {
  name                = "ag-mvenc-${var.environment}"
  resource_group_name = data.azurerm_resource_group.dev.name
  short_name          = "mvencalert"

  email_receiver {
    name          = "admin"
    email_address = var.admin_email
  }

  tags = var.tags
}

# Alerta de falha da função — baseado em log (App Insights), não em métrica de
# plataforma: o Flex Consumption não expõe "FunctionExecutionCount"/Status como o
# Consumption clássico (confirmado com `az monitor metrics list-definitions` contra a
# Function real, já implantada — ver Pendências da T12 no PLANO.md). O texto
# "Falha [" é o mesmo que run.ps1 grava via Write-Warning pra cada item que falhou
# (T08) — cada linha vira um `trace` no App Insights.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "function_failures" {
  name                 = "alert-mvenc-function-failures-${var.environment}"
  resource_group_name  = data.azurerm_resource_group.dev.name
  location             = data.azurerm_resource_group.dev.location
  scopes               = [azurerm_log_analytics_workspace.main.id]
  description          = "A Function App registrou pelo menos uma falha de verificação de item no último dia."
  severity             = 2
  evaluation_frequency = "PT6H"
  window_duration      = "P1D"
  # A Workspace nasce vazia — a tabela "traces" só existe depois que o App Insights
  # ingerir alguma telemetria pela primeira vez (a Function ainda não rodou no
  # primeiro apply). Sem isso, a criação falha com "Failed to resolve table...
  # traces" (achado na prática — ver Pendências da T12 no PLANO.md).
  skip_query_validation = true

  criteria {
    query                   = <<-KQL
      traces
      | where message startswith "Falha ["
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.main.id]
  }

  tags = var.tags
}
