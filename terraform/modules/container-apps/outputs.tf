# modules/container-apps/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs, names, and public FQDNs for downstream callers. Maps are
# keyed by app name (the same key `for_each` uses) so callers can look up
# individual apps without pattern-matching on the resource name.
#
# Downstream consumers: module 12 (monitoring) is expected to attach
# diagnostic settings using `app_ids`; README / CI publishes URLs from
# `app_fqdns`.
# -----------------------------------------------------------------------------

output "app_ids" {
  description = "Map from app name → full Azure Resource ID of its Container App. Use as `scope` for per-app role assignments or diagnostic settings."
  value       = { for k, a in azurerm_container_app.app : k => a.id }
}

output "app_names" {
  description = "Map from app name → deployed resource name (`ca-<env>-<app>`). Convenience for `az containerapp show -n <this>`."
  value       = { for k, a in azurerm_container_app.app : k => a.name }
}

output "app_fqdns" {
  description = "Map from app name → externally-reachable FQDN (`<app>.<cae_default_domain>`), or `null` for apps where ingress is disabled. Publish these URLs in the README and to callers of the API."
  value       = { for k, a in azurerm_container_app.app : k => try(a.ingress[0].fqdn, null) }
}

output "app_latest_revisions" {
  description = "Map from app name → name of the latest deployed revision (e.g. `ca-dev-api--<hash>`). Handy for `az containerapp revision show` and rollback commands."
  value       = { for k, a in azurerm_container_app.app : k => a.latest_revision_name }
}
