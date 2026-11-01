# roots/18-ai-search/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs.
# -----------------------------------------------------------------------------

output "search_service_id" {
  description = "Resource ID of srch-<workload>ai-<env>-<region>."
  value       = module.ai_search.search_service_id
}

output "search_service_name" {
  description = "Name of the AI Search service."
  value       = module.ai_search.search_service_name
}

output "storage_account_name" {
  description = "Name of the storage account indexed by the search service."
  value       = module.ai_search.storage_account_name
}

output "container_name" {
  description = "Blob container that holds the documents to index."
  value       = module.ai_search.container_name
}
