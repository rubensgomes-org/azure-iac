# envs/dev/04-managed-identities/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

output "uami_app_id" {
  description = "Full Azure Resource ID of the shared UAMI."
  value       = module.managed_identities.uami_app_id
}

output "uami_app_name" {
  description = "UAMI name (`id-<env>-app`)."
  value       = module.managed_identities.uami_app_name
}

output "uami_app_principal_id" {
  description = "Entra ID object ID for RBAC grants and PG AAD principal registration."
  value       = module.managed_identities.uami_app_principal_id
}

output "uami_app_client_id" {
  description = "OAuth client ID. Set as AZURE_CLIENT_ID env var on every Container App."
  value       = module.managed_identities.uami_app_client_id
}

output "uami_app_tenant_id" {
  description = "Tenant ID that owns the UAMI."
  value       = module.managed_identities.uami_app_tenant_id
}

output "uami_app_location" {
  description = "Azure region of the UAMI."
  value       = module.managed_identities.uami_app_location
}
