# roots/15-foundry/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
# -----------------------------------------------------------------------------

output "foundry_id" {
  description = "Resource ID of aif-<workload>-<env>."
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
