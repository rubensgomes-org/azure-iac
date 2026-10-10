# modules/app-configuration/outputs.tf
# -----------------------------------------------------------------------------
# Names MUST match what the downstream modules read — do not rename without
# updating every consumer.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
# -----------------------------------------------------------------------------

output "appcs_id" {
  description = "Full Azure Resource ID of the App Configuration store."
  value       = azurerm_app_configuration.this.id
}

output "appcs_name" {
  description = "Store name (`appcs-<workload>-<env>`)."
  value       = azurerm_app_configuration.this.name
}

output "appcs_endpoint" {
  description = "Data-plane endpoint (`https://<name>.azconfig.io`). Injected into apps as APP_CONFIG_ENDPOINT."
  value       = azurerm_app_configuration.this.endpoint
}

output "appcs_location" {
  description = "Azure region of the store."
  value       = azurerm_app_configuration.this.location
}

output "appcs_principal_id" {
  description = "principal_id of the store's system-assigned identity. Granted Key Vault access by module 06."
  value       = azurerm_app_configuration.this.identity[0].principal_id
}

output "appcs_role_assignment_id" {
  description = "ID of the `App Configuration Data Reader` role assignment granted to the shared UAMI."
  value       = azurerm_role_assignment.uami_data_reader.id
}
