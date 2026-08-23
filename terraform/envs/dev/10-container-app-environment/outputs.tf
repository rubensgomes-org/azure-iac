# envs/dev/10-container-app-environment/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
#
# Downstream consumer: module 11 (container-apps) reads `cae_id`.
# -----------------------------------------------------------------------------

output "cae_id" {
  description = "Full Azure Resource ID of the Container App Environment. Consumed by module 11."
  value       = module.container_app_environment.cae_id
}

output "cae_name" {
  description = "Environment name (`cae-<env>`)."
  value       = module.container_app_environment.cae_name
}

output "cae_default_domain" {
  description = "Default DNS suffix Azure assigns to apps in this environment (`<random>.<region>.azurecontainerapps.io`). App FQDNs land at `<app>.<cae_default_domain>`."
  value       = module.container_app_environment.cae_default_domain
}

output "cae_static_ip_address" {
  description = "Public static IP that serves ingress for every external app in this environment."
  value       = module.container_app_environment.cae_static_ip_address
}

output "cae_location" {
  description = "Azure region of the environment."
  value       = module.container_app_environment.cae_location
}
