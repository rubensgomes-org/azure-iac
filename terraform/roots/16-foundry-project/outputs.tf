# roots/16-foundry-project/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs.
# -----------------------------------------------------------------------------

output "foundry_project_id" {
  description = "Resource ID of proj-<workload>ai<suffix>-<env>-<region>."
  value       = module.foundry_project.foundry_project_id
}

output "foundry_project_name" {
  description = "Name of the Foundry project."
  value       = module.foundry_project.foundry_project_name
}

output "foundry_project_principal_id" {
  description = "Object ID of the project's system-assigned identity."
  value       = module.foundry_project.foundry_project_principal_id
}
