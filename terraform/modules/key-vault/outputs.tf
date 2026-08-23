# modules/key-vault/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs and URIs for downstream callers. Names MUST match what the
# plan (§4) commits to — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

output "kv_id" {
  description = "Full Azure Resource ID of the Key Vault. Use as `scope` for further role assignments outside this module."
  value       = azurerm_key_vault.this.id
}

output "kv_name" {
  description = "Key Vault name (`kv-<env>-<prefix>-<random>`). Needed for `az keyvault purge` after destroy — capture this output before running destroy."
  value       = azurerm_key_vault.this.name
}

output "kv_uri" {
  description = "DNS URI of the vault (`https://<name>.vault.azure.net/`). Apps pass this as an env var (e.g. `KEY_VAULT_URI`) so DefaultAzureCredential + SecretClient can reach the data plane."
  value       = azurerm_key_vault.this.vault_uri
}

output "kv_location" {
  description = "Azure region of the Key Vault."
  value       = azurerm_key_vault.this.location
}

output "kv_role_assignment_id" {
  description = "ID of the `Key Vault Secrets User` role assignment granted to the shared UAMI. Exposed so downstream modules or scripts can reference it (rare)."
  value       = azurerm_role_assignment.uami_secrets_user.id
}
