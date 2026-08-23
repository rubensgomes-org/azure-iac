# envs/dev/07-storage/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

output "sa_id" {
  description = "Full Azure Resource ID of the storage account."
  value       = module.storage.sa_id
}

output "sa_name" {
  description = "Storage account name (`st<env>app<random>`). Passed to Container Apps as `STORAGE_ACCOUNT_NAME` env var."
  value       = module.storage.sa_name
}

output "sa_primary_blob_endpoint" {
  description = "Primary blob endpoint URL (`https://<name>.blob.core.windows.net/`)."
  value       = module.storage.sa_primary_blob_endpoint
}

output "sa_location" {
  description = "Azure region of the storage account."
  value       = module.storage.sa_location
}

output "sa_role_assignment_id" {
  description = "ID of the `Storage Blob Data Contributor` role assignment granted to the shared UAMI."
  value       = module.storage.sa_role_assignment_id
}

output "container_names" {
  description = "Map from app name → blob container name. Consumed by module 11 to set each app's `STORAGE_CONTAINER_NAME` env var."
  value       = module.storage.container_names
}

output "container_ids" {
  description = "Map from app name → full Azure Resource ID of its blob container."
  value       = module.storage.container_ids
}
