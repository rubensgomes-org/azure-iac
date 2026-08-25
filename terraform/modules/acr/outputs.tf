# modules/acr/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs and identifiers for downstream callers. Names MUST match
# what the plan (§4) commits to — do not rename without updating every
# consumer.
# -----------------------------------------------------------------------------

output "acr_id" {
  description = "Full Azure Resource ID of the registry. Use as `scope` for further role assignments outside this module."
  value       = azurerm_container_registry.this.id
}

output "acr_name" {
  description = "Registry name (explicit, from `var.acr_name`; `rubensdevacr` in dev). Consumed by CI/CD for `docker login` and by `az acr` commands."
  value       = azurerm_container_registry.this.name
}

output "acr_login_server" {
  description = "Registry login server (`<name>.azurecr.io`). Passed to `azurerm_container_app.registries.server` (module 11) so apps can pull images by full reference."
  value       = azurerm_container_registry.this.login_server
}

output "acr_location" {
  description = "Azure region of the registry."
  value       = azurerm_container_registry.this.location
}

output "acr_role_assignment_id" {
  description = "ID of the `AcrPull` role assignment granted to the shared UAMI."
  value       = azurerm_role_assignment.uami_acrpull.id
}
