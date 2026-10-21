# roots/15-foundry/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs.
# -----------------------------------------------------------------------------

output "foundry_id" {
  description = "Resource ID of aif-<workload>-<env>-<region>."
  value       = module.foundry.foundry_id
}

output "foundry_name" {
  description = "Name of the Foundry resource."
  value       = module.foundry.foundry_name
}

output "foundry_project_id" {
  description = "Resource ID of proj-<workload>-<env>."
  value       = module.foundry.foundry_project_id
}

output "foundry_project_name" {
  description = "Name of the Foundry project."
  value       = module.foundry.foundry_project_name
}

output "app_insights_id" {
  description = "Resource ID of appi-<workload>ai-<env>. Null when disabled."
  value       = module.foundry.app_insights_id
}

output "app_insights_name" {
  description = "Name of the Application Insights connected for tracing. Null when disabled."
  value       = module.foundry.app_insights_name
}
