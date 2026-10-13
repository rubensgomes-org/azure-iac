# roots/14-app-gateway/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
# -----------------------------------------------------------------------------

output "agw_id" {
  description = "Resource ID of agw-<workload>-<env>."
  value       = module.app_gateway.agw_id
}

output "agw_name" {
  description = "Name of the gateway."
  value       = module.app_gateway.agw_name
}

output "agw_public_ip_address" {
  description = "Public IP address of the gateway."
  value       = module.app_gateway.agw_public_ip_address
}

output "agw_public_fqdn" {
  description = "Public DNS name `<dns_label>.<location>.cloudapp.azure.com`."
  value       = module.app_gateway.agw_public_fqdn
}

output "agw_public_url" {
  description = "Public URL of the exposed app."
  value       = module.app_gateway.agw_public_url
}
