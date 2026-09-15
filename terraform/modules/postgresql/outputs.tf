# modules/postgresql/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs and identifiers for downstream callers. Names MUST match
# what downstream modules read — do not rename without updating every
# consumer.
# -----------------------------------------------------------------------------

output "pg_server_id" {
  description = "Full Azure Resource ID of the Flexible Server. Use as `scope` for future role assignments or metric collectors."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "pg_server_name" {
  description = "Server name (`psql-<env>-<random>`). Used in the FQDN — captured before `terraform destroy` so post-destroy `az` calls can find the tombstoned server if reprovision needs to run inside the 7-day window."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "pg_fqdn" {
  description = "Fully-qualified server hostname (`<name>.postgres.database.azure.com`). Passed to Container Apps as `POSTGRES_HOST`."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "pg_version" {
  description = "PostgreSQL engine major version. Handy for client-side driver pinning."
  value       = azurerm_postgresql_flexible_server.this.version
}

output "pg_location" {
  description = "Azure region of the Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.location
}

output "pg_databases" {
  description = "Map from app name → database name (identity on this iteration — DB name equals app name). Consumed by module 11 to set each app's `POSTGRES_DB` env var."
  value       = { for k, d in azurerm_postgresql_flexible_server_database.app : k => d.name }
}

output "pg_database_ids" {
  description = "Map from app name → full Azure Resource ID of its database. Handy for future per-database role assignments (e.g. via `azapi_resource`)."
  value       = { for k, d in azurerm_postgresql_flexible_server_database.app : k => d.id }
}

output "pg_admin_group_object_id" {
  description = "Echo of the Entra group set as PG administrator. Downstream tooling that wants to check membership can read it here without a second lookup."
  value       = var.pg_entra_admin_group_object_id
}

output "pg_admin_login" {
  description = "Display name of the Entra admin group. Same value apps would use as `PGUSER` if they wanted admin-level access — apps use `uami_name` instead."
  value       = var.pg_entra_admin_group_name
}
