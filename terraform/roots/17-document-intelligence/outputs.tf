# roots/17-document-intelligence/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs.
# -----------------------------------------------------------------------------

output "document_intelligence_id" {
  description = "Resource ID of di-<workload>ai-<env>-<region>."
  value       = module.document_intelligence.document_intelligence_id
}

output "document_intelligence_name" {
  description = "Name of the Document Intelligence resource."
  value       = module.document_intelligence.document_intelligence_name
}

output "training_storage_account_name" {
  description = "Name of the training data storage account."
  value       = module.document_intelligence.training_storage_account_name
}

output "training_container_name" {
  description = "Blob container that holds the training data."
  value       = module.document_intelligence.training_container_name
}
