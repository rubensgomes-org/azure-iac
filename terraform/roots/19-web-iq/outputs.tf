# roots/19-web-iq/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs.
# -----------------------------------------------------------------------------

output "web_iq_id" {
  description = "Resource ID of wiq-<workload>ai-<env>."
  value       = module.web_iq.web_iq_id
}

output "web_iq_name" {
  description = "Name of the Web IQ account."
  value       = module.web_iq.web_iq_name
}
