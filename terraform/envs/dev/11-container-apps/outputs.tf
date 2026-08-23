# envs/dev/11-container-apps/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules (12-monitoring)
# and human callers can read them. Names MUST match what downstream modules
# request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

output "app_ids" {
  description = "Map from app name → full Azure Resource ID. Consumed by module 12 for per-app diagnostic settings."
  value       = module.container_apps.app_ids
}

output "app_names" {
  description = "Map from app name → deployed resource name (`ca-<env>-<app>`). Convenience for `az containerapp show -n <this>`."
  value       = module.container_apps.app_names
}

output "app_fqdns" {
  description = "Map from app name → externally-reachable FQDN, or `null` when ingress is disabled. Publish these URLs in the README and to API callers."
  value       = module.container_apps.app_fqdns
}

output "app_latest_revisions" {
  description = "Map from app name → latest revision name (e.g. `ca-dev-api--<hash>`). Handy for `az containerapp revision show` and rollback commands."
  value       = module.container_apps.app_latest_revisions
}
