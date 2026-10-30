# modules/foundry-project/outputs.tf
# -----------------------------------------------------------------------------
# Publishes names and IDs only. Endpoints are deliberately omitted.
# -----------------------------------------------------------------------------

output "foundry_project_id" {
  description = "Resource ID of proj-<workload>ai<name_suffix>-<env>-<region>."
  value       = azurerm_cognitive_account_project.this.id
}

output "foundry_project_name" {
  description = "Name of the Foundry project."
  value       = azurerm_cognitive_account_project.this.name
}

output "foundry_project_principal_id" {
  description = "Object ID of the project's system-assigned identity."
  value       = azurerm_cognitive_account_project.this.identity[0].principal_id
}
