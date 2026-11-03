# modules/web-iq/outputs.tf
# -----------------------------------------------------------------------------
# Publishes names and IDs only. Endpoints and keys are deliberately omitted.
# -----------------------------------------------------------------------------

output "web_iq_id" {
  description = "Resource ID of wiq-<workload>ai-<env>."
  value       = azapi_resource.this.id
}

output "web_iq_name" {
  description = "Name of the Web IQ account."
  value       = azapi_resource.this.name
}
