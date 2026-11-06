# modules/language/outputs.tf
# -----------------------------------------------------------------------------
# Publishes names and IDs only. Endpoints are deliberately omitted.
# -----------------------------------------------------------------------------

output "language_id" {
  description = "Resource ID of lang-<workload>ai-<env>-<region>."
  value       = azurerm_cognitive_account.this.id
}

output "language_name" {
  description = "Name of the Language resource."
  value       = azurerm_cognitive_account.this.name
}
