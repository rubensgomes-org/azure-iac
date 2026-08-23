# envs/dev/12-monitoring/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs. Module 12 is the last module in
# the dependency chain, so nothing downstream reads these via
# `data.terraform_remote_state` today — the outputs exist for human use
# (copy the connection string into a running app, or find the action
# group ID for a portal-driven alert rule) and for a future revision of
# module 11 that wants to inject `APPLICATIONINSIGHTS_CONNECTION_STRING`
# via Terraform (rather than through the app's own configuration).
# -----------------------------------------------------------------------------

output "ai_id" {
  description = "Full Azure Resource ID of the Application Insights component."
  value       = module.monitoring.ai_id
}

output "ai_name" {
  description = "App Insights component name (`appi-<env>`)."
  value       = module.monitoring.ai_name
}

output "ai_app_id" {
  description = "App Insights `app_id` GUID. Used by the Azure Monitor Query API."
  value       = module.monitoring.ai_app_id
}

output "ai_instrumentation_key" {
  description = "Legacy per-component instrumentation key (sensitive). Prefer `ai_connection_string`."
  value       = module.monitoring.ai_instrumentation_key
  sensitive   = true
}

output "ai_connection_string" {
  description = "Preferred telemetry endpoint carrier (sensitive). Set as `APPLICATIONINSIGHTS_CONNECTION_STRING` on Container Apps."
  value       = module.monitoring.ai_connection_string
  sensitive   = true
}

output "action_group_ids" {
  description = "Map from action group logical name → full Azure Resource ID. One entry today (`ops`)."
  value       = module.monitoring.action_group_ids
}

output "diagnostic_setting_ids" {
  description = "Map from target name → diag setting ID. Informational; no downstream module consumes it."
  value       = module.monitoring.diagnostic_setting_ids
}
