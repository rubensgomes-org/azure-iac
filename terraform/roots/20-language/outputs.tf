# roots/20-language/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs.
# -----------------------------------------------------------------------------

output "language_id" {
  description = "Resource ID of lang-<workload>ai-<env>-<region>."
  value       = module.language.language_id
}

output "language_name" {
  description = "Name of the Language resource."
  value       = module.language.language_name
}
