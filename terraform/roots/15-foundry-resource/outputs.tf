# roots/15-foundry-resource/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs.
# -----------------------------------------------------------------------------

output "foundry_id" {
  description = "Resource ID of aif-<workload>ai-<env>-<region>."
  value       = module.foundry_resource.foundry_id
}

output "foundry_name" {
  description = "Name of the Foundry resource."
  value       = module.foundry_resource.foundry_name
}

output "app_insights_id" {
  description = "Resource ID of appi-<workload>ai-<env>-<region>. Null when disabled."
  value       = module.foundry_resource.app_insights_id
}

output "app_insights_name" {
  description = "Name of the Application Insights connected for tracing. Null when disabled."
  value       = module.foundry_resource.app_insights_name
}
