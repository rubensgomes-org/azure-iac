# modules/foundry-resource/outputs.tf
# -----------------------------------------------------------------------------
# Publishes names and IDs only. Endpoints and keys are deliberately omitted.
# -----------------------------------------------------------------------------

output "foundry_id" {
  description = "Resource ID of aif-<workload>ai-<env>-<region>."
  value       = azurerm_cognitive_account.this.id
}

output "foundry_name" {
  description = "Name of the Foundry resource."
  value       = azurerm_cognitive_account.this.name
}

output "app_insights_id" {
  description = "Resource ID of appi-<workload>ai-<env>-<region>. Null when disabled."
  value       = one(azurerm_application_insights.this[*].id)
}

output "app_insights_name" {
  description = "Name of the Application Insights connected for tracing. Null when disabled."
  value       = one(azurerm_application_insights.this[*].name)
}
