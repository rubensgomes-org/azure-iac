# envs/dev/09-postgresql/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

output "pg_server_id" {
  description = "Full Azure Resource ID of the Flexible Server."
  value       = module.postgresql.pg_server_id
}

output "pg_server_name" {
  description = "Server name (`psql-<env>-<random>`). Capture BEFORE `terraform destroy` if you want to check the 7-day soft-delete tombstone afterwards."
  value       = module.postgresql.pg_server_name
}

output "pg_fqdn" {
  description = "Fully-qualified server hostname. Passed to Container Apps as `POSTGRES_HOST`."
  value       = module.postgresql.pg_fqdn
}

output "pg_version" {
  description = "PostgreSQL engine major version."
  value       = module.postgresql.pg_version
}

output "pg_location" {
  description = "Azure region of the Flexible Server."
  value       = module.postgresql.pg_location
}

output "pg_databases" {
  description = "Map from app name → database name. Consumed by module 11 to set each app's `POSTGRES_DB` env var."
  value       = module.postgresql.pg_databases
}

output "pg_database_ids" {
  description = "Map from app name → full Azure Resource ID of its database."
  value       = module.postgresql.pg_database_ids
}

output "pg_admin_group_object_id" {
  description = "Echo of the Entra group set as PG administrator."
  value       = module.postgresql.pg_admin_group_object_id
}

output "pg_admin_login" {
  description = "Display name of the Entra admin group."
  value       = module.postgresql.pg_admin_login
}
