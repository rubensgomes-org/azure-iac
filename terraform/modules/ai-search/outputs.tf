# modules/ai-search/outputs.tf
# -----------------------------------------------------------------------------
# Publishes names and IDs only. Endpoints are deliberately omitted.
# -----------------------------------------------------------------------------

output "search_service_id" {
  description = "Resource ID of srch-<workload>ai-<env>-<region>."
  value       = azurerm_search_service.this.id
}

output "search_service_name" {
  description = "Name of the AI Search service."
  value       = azurerm_search_service.this.name
}

output "storage_account_name" {
  description = "Name of the storage account indexed by the search service."
  value       = azurerm_storage_account.this.name
}

output "container_name" {
  description = "Blob container that holds the documents to index."
  value       = azapi_resource.documents_container.name
}
