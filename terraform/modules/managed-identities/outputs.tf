# modules/managed-identities/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs and identifiers for the shared UAMI so downstream modules
# can wire RBAC assignments and attach the identity to Container Apps.
#
# Terminology (Azure UAMIs expose three distinct identifiers):
#   - `id`           = Azure Resource ID (long "/subscriptions/.../userAssignedIdentities/id-<env>-app")
#                      Used by: azurerm_container_app.identity_ids,
#                               azurerm_role_assignment.principal_id (for the resource itself, less common),
#                               ACR/CAE identity blocks.
#   - `principal_id` = Entra ID object ID of the identity's service principal
#                      Used by: azurerm_role_assignment.principal_id (the RBAC principal),
#                               azurerm_key_vault_access_policy.object_id,
#                               PG's pgaadauth_create_principal to register the AAD role.
#   - `client_id`    = OAuth client ID
#                      Used by: apps at runtime via AZURE_CLIENT_ID env var so
#                               DefaultAzureCredential picks THIS identity when
#                               multiple UAMIs are attached.
# -----------------------------------------------------------------------------

output "uami_app_id" {
  description = "Full Azure Resource ID of the shared UAMI. Use for azurerm_container_app.identity_ids and identity blocks on other resources."
  value       = azurerm_user_assigned_identity.app.id
}

output "uami_app_name" {
  description = "UAMI name (`id-<env>-app`). Also the login name registered in PG when the shared UAMI is created as an AAD principal (module 09)."
  value       = azurerm_user_assigned_identity.app.name
}

output "uami_app_principal_id" {
  description = "Entra ID object ID of the identity's service principal. Use for azurerm_role_assignment.principal_id (RBAC grants) and PG's pgaadauth_create_principal."
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "uami_app_client_id" {
  description = "OAuth client ID of the UAMI. Pass as AZURE_CLIENT_ID env var on every Container App so DefaultAzureCredential selects this identity."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "uami_app_tenant_id" {
  description = "Tenant ID that owns the UAMI. Convenient for callers that need it without a second azurerm_client_config lookup."
  value       = azurerm_user_assigned_identity.app.tenant_id
}

output "uami_app_location" {
  description = "Azure region of the UAMI."
  value       = azurerm_user_assigned_identity.app.location
}
