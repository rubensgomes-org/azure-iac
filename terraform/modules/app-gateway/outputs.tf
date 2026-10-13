# modules/app-gateway/outputs.tf
# -----------------------------------------------------------------------------
# Publishes the gateway's identity and public endpoint.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
# -----------------------------------------------------------------------------

output "agw_id" {
  description = "Resource ID of agw-<workload>-<env>."
  value       = azurerm_application_gateway.this.id
}

output "agw_name" {
  description = "Name of the gateway. Convenience for `az network application-gateway show-backend-health -n <this>`."
  value       = azurerm_application_gateway.this.name
}

output "agw_public_ip_address" {
  description = "Public IP address of the gateway. Changes when the gateway root is destroyed and recreated."
  value       = azurerm_public_ip.this.ip_address
}

output "agw_public_fqdn" {
  description = "Public DNS name `<dns_label>.<location>.cloudapp.azure.com`."
  value       = azurerm_public_ip.this.fqdn
}

output "agw_public_url" {
  description = "Public URL of the exposed app."
  value       = "http://${azurerm_public_ip.this.fqdn}"
}
