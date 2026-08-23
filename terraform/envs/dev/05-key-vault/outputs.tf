# envs/dev/05-key-vault/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

output "kv_id" {
  description = "Full Azure Resource ID of the Key Vault."
  value       = module.key_vault.kv_id
}

output "kv_name" {
  description = "Key Vault name (`kv-<env>-<prefix>-<random>`). Capture BEFORE destroy for `az keyvault purge`."
  value       = module.key_vault.kv_name
}

output "kv_uri" {
  description = "Vault DNS URI (`https://<name>.vault.azure.net/`). Apps pass this as an env var for DefaultAzureCredential + SecretClient."
  value       = module.key_vault.kv_uri
}

output "kv_location" {
  description = "Azure region of the Key Vault."
  value       = module.key_vault.kv_location
}

output "kv_role_assignment_id" {
  description = "ID of the `Key Vault Secrets User` role assignment granted to the shared UAMI."
  value       = module.key_vault.kv_role_assignment_id
}
