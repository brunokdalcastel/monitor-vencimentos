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

resource "azurerm_monitor_metric_alert" "function_failures" {
  name                = "alert-mvenc-function-failures-${var.environment}"
  resource_group_name = data.azurerm_resource_group.dev.name
  scopes              = [azurerm_function_app_flex_consumption.main.id]
  description         = "A Function App registrou pelo menos uma execução com falha na última hora."
  severity            = 2
  frequency           = "PT1H"
  window_size         = "PT1H"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Failure"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  tags = var.tags
}
