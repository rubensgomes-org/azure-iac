# modules/foundry/outputs.tf
# -----------------------------------------------------------------------------
# Publishes names and IDs only. Endpoints and keys are deliberately omitted.
# -----------------------------------------------------------------------------

output "foundry_id" {
  description = "Resource ID of aif-<workload>-<env>."
  value       = azurerm_cognitive_account.this.id
}

output "foundry_name" {
  description = "Name of the Foundry resource."
  value       = azurerm_cognitive_account.this.name
}

output "foundry_project_id" {
  description = "Resource ID of proj-<workload>-<env>."
  value       = azurerm_cognitive_account_project.this.id
}

output "foundry_project_name" {
  description = "Name of the Foundry project."
  value       = azurerm_cognitive_account_project.this.name
}
