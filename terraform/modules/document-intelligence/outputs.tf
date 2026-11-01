# modules/document-intelligence/outputs.tf
# -----------------------------------------------------------------------------
# Publishes names and IDs only. Endpoints are deliberately omitted.
# -----------------------------------------------------------------------------

output "document_intelligence_id" {
  description = "Resource ID of di-<workload>ai-<env>-<region>."
  value       = azurerm_cognitive_account.this.id
}

output "document_intelligence_name" {
  description = "Name of the Document Intelligence resource."
  value       = azurerm_cognitive_account.this.name
}

output "training_storage_account_name" {
  description = "Name of the training data storage account."
  value       = azurerm_storage_account.training.name
}

output "training_container_name" {
  description = "Blob container that holds the training data."
  value       = azapi_resource.training_container.name
}
