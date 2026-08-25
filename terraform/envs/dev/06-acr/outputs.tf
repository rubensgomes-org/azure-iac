# envs/dev/06-acr/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

output "acr_id" {
  description = "Full Azure Resource ID of the container registry."
  value       = module.acr.acr_id
}

output "acr_name" {
  description = "Registry name (explicit, from `var.acr_name`; `rubensdevacr` in dev). Consumed by CI/CD for `docker login` and by `az acr` commands."
  value       = module.acr.acr_name
}

output "acr_login_server" {
  description = "Registry login server (`<name>.azurecr.io`). Passed to `azurerm_container_app.registries.server` (module 11) so apps can pull images by full reference."
  value       = module.acr.acr_login_server
}

output "acr_location" {
  description = "Azure region of the registry."
  value       = module.acr.acr_location
}

output "acr_role_assignment_id" {
  description = "ID of the `AcrPull` role assignment granted to the shared UAMI."
  value       = module.acr.acr_role_assignment_id
}
