# roots/05-app-configuration/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules (06, 12) can
# read them via `data.terraform_remote_state`. Do not rename without updating
# every consumer.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
# -----------------------------------------------------------------------------

output "appcs_id" {
  description = "Full Azure Resource ID of the App Configuration store."
  value       = module.app_configuration.appcs_id
}

output "appcs_name" {
  description = "Store name (`appcs-<workload>-<env>`)."
  value       = module.app_configuration.appcs_name
}

output "appcs_endpoint" {
  description = "Data-plane endpoint (`https://<name>.azconfig.io`). Injected into apps as APP_CONFIG_ENDPOINT."
  value       = module.app_configuration.appcs_endpoint
}

output "appcs_location" {
  description = "Azure region of the store."
  value       = module.app_configuration.appcs_location
}

output "appcs_principal_id" {
  description = "principal_id of the store's system-assigned identity. Granted Key Vault access by module 06."
  value       = module.app_configuration.appcs_principal_id
}

output "appcs_role_assignment_id" {
  description = "ID of the `App Configuration Data Reader` role assignment granted to the shared UAMI."
  value       = module.app_configuration.appcs_role_assignment_id
}
