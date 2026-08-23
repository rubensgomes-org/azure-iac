# envs/dev/03-log-analytics/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

output "law_id" {
  description = "Full Azure Resource ID of the workspace."
  value       = module.log_analytics.law_id
}

output "law_name" {
  description = "Workspace name (`log-<env>-<random>`)."
  value       = module.log_analytics.law_name
}

output "law_workspace_id" {
  description = "Workspace customer_id GUID. Consumed by Container App Environment (module 10)."
  value       = module.log_analytics.law_workspace_id
}

output "law_primary_shared_key" {
  description = "Primary shared key. Sensitive; legacy agent auth."
  value       = module.log_analytics.law_primary_shared_key
  sensitive   = true
}

output "law_location" {
  description = "Azure region of the workspace."
  value       = module.log_analytics.law_location
}
