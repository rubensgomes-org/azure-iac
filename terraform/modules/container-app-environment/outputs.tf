# modules/container-app-environment/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs, names, and endpoints for downstream callers. Module 11
# (container-apps) consumes `cae_id`; DNS wiring and browser-facing docs
# consume `cae_default_domain` and `cae_static_ip_address`.
#
# See docs/PROVISIONING_PLAN.md §4 for who consumes what.
# -----------------------------------------------------------------------------

output "cae_id" {
  description = "Full Azure Resource ID of the Container App Environment. Every `azurerm_container_app` in module 11 sets `container_app_environment_id = <this>`."
  value       = azurerm_container_app_environment.this.id
}

output "cae_name" {
  description = "Environment name (`cae-<env>`). Convenience for `az containerapp env show -n <this>`."
  value       = azurerm_container_app_environment.this.name
}

output "cae_default_domain" {
  description = "Default DNS suffix Azure assigns to apps in this environment (e.g. `<random>.centralus.azurecontainerapps.io`). App FQDNs land at `<app-name>.<cae_default_domain>`. Used by module 11 outputs and any doc that publishes URLs."
  value       = azurerm_container_app_environment.this.default_domain
}

output "cae_static_ip_address" {
  description = "Public static IP that serves ingress for every external app in this environment. Point a CNAME / A record here if you attach a custom domain. Null-ish when `internal_load_balancer_enabled = true`."
  value       = azurerm_container_app_environment.this.static_ip_address
}

output "cae_location" {
  description = "Azure region of the environment. Must match `subnet_app` and (for a shared LAW) the workspace region."
  value       = azurerm_container_app_environment.this.location
}
