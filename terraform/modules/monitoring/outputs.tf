# modules/monitoring/outputs.tf
# -----------------------------------------------------------------------------
# Publishes App Insights identifiers and action group IDs. Diagnostic
# settings are not exported — they're implementation detail with no
# downstream consumer.
#
# `ai_connection_string` is what module 11 (or a future revision of it)
# passes to apps as `APPLICATIONINSIGHTS_CONNECTION_STRING` — the Azure
# Monitor OpenTelemetry SDK reads that env var directly.
# -----------------------------------------------------------------------------

output "ai_id" {
  description = "Full Azure Resource ID of the Application Insights component."
  value       = azurerm_application_insights.this.id
}

output "ai_name" {
  description = "App Insights component name (`appi-<env>`)."
  value       = azurerm_application_insights.this.name
}

output "ai_app_id" {
  description = "App Insights `app_id` GUID. Used by the Azure Monitor Query API and PowerBI connectors — NOT the same as the connection string or instrumentation key."
  value       = azurerm_application_insights.this.app_id
}

output "ai_instrumentation_key" {
  description = "Legacy per-component instrumentation key. Kept as an output for old SDKs; new code should use `ai_connection_string` instead. Marked sensitive to keep it out of plan output."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "ai_connection_string" {
  description = "Preferred telemetry endpoint carrier. Pass to apps as `APPLICATIONINSIGHTS_CONNECTION_STRING`; the Azure Monitor OpenTelemetry SDK reads it directly. Sensitive because it contains the ingestion-key equivalent."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "action_group_ids" {
  description = "Map from action group logical name → full Azure Resource ID. One entry today (`ops`); grows when more receivers/routes are added in main.tf. Alert rule resources reference values here as `action { action_group_id = <this> }`."
  value = {
    ops = azurerm_monitor_action_group.ops.id
  }
}

output "diagnostic_setting_ids" {
  description = "Map from short target name → full ID of the diagnostic setting attached to that target. Handy for `az monitor diagnostic-settings show` and future automation; no downstream module consumes this."
  value = {
    key_vault    = azurerm_monitor_diagnostic_setting.key_vault.id
    acr          = azurerm_monitor_diagnostic_setting.acr.id
    storage_blob = azurerm_monitor_diagnostic_setting.storage_blob.id
    service_bus  = azurerm_monitor_diagnostic_setting.service_bus.id
    postgresql   = azurerm_monitor_diagnostic_setting.postgresql.id
  }
}
