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
