# modules/storage/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs and identifiers for downstream callers. Names MUST match
# what the plan (§4) commits to — do not rename without updating every
# consumer.
# -----------------------------------------------------------------------------

output "sa_id" {
  description = "Full Azure Resource ID of the storage account. Use as `scope` for further role assignments outside this module."
  value       = azurerm_storage_account.this.id
}

output "sa_name" {
  description = "Storage account name (`st<env>app<random>`). Passed to Container Apps as `STORAGE_ACCOUNT_NAME` env var — apps compose the blob endpoint from it via `DefaultAzureCredential`."
  value       = azurerm_storage_account.this.name
}

output "sa_primary_blob_endpoint" {
  description = "Primary blob endpoint URL (`https://<name>.blob.core.windows.net/`). Consumed by apps and by any future PE wiring."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "sa_location" {
  description = "Azure region of the storage account."
  value       = azurerm_storage_account.this.location
}

output "sa_role_assignment_id" {
  description = "ID of the `Storage Blob Data Contributor` role assignment granted to the shared UAMI."
  value       = azurerm_role_assignment.uami_blob_contributor.id
}

output "container_names" {
  description = "Map from app name → blob container name. Container name = app name today. Consumed by module 11 to set each app's `STORAGE_CONTAINER_NAME` env var."
  value       = { for k, c in azapi_resource.container : k => c.name }
}

output "container_ids" {
  description = "Map from app name → full Azure Resource ID of its blob container. Handy for future per-container role assignments."
  value       = { for k, c in azapi_resource.container : k => c.id }
}
