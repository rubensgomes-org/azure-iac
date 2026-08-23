# envs/dev/01-resource-groups/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

# ---- Platform RG (managed identities, KV, ACR) -----------------------------

output "rg_platform_name" {
  description = "Name of rg-<env>-platform."
  value       = module.resource_groups.rg_platform_name
}

output "rg_platform_id" {
  description = "Resource ID of rg-<env>-platform."
  value       = module.resource_groups.rg_platform_id
}

output "rg_platform_location" {
  description = "Azure region of rg-<env>-platform."
  value       = module.resource_groups.rg_platform_location
}

# ---- Network RG (VNet, NSGs, private DNS) ----------------------------------

output "rg_network_name" {
  description = "Name of rg-<env>-network."
  value       = module.resource_groups.rg_network_name
}

output "rg_network_id" {
  description = "Resource ID of rg-<env>-network."
  value       = module.resource_groups.rg_network_id
}

output "rg_network_location" {
  description = "Azure region of rg-<env>-network."
  value       = module.resource_groups.rg_network_location
}

# ---- Data RG (PostgreSQL, Service Bus, Storage) ----------------------------

output "rg_data_name" {
  description = "Name of rg-<env>-data."
  value       = module.resource_groups.rg_data_name
}

output "rg_data_id" {
  description = "Resource ID of rg-<env>-data."
  value       = module.resource_groups.rg_data_id
}

output "rg_data_location" {
  description = "Azure region of rg-<env>-data."
  value       = module.resource_groups.rg_data_location
}

# ---- App RG (Container App Environment, Container Apps) --------------------

output "rg_app_name" {
  description = "Name of rg-<env>-app."
  value       = module.resource_groups.rg_app_name
}

output "rg_app_id" {
  description = "Resource ID of rg-<env>-app."
  value       = module.resource_groups.rg_app_id
}

output "rg_app_location" {
  description = "Azure region of rg-<env>-app."
  value       = module.resource_groups.rg_app_location
}

# ---- Observability RG (Log Analytics, App Insights, Action Groups) ---------

output "rg_observability_name" {
  description = "Name of rg-<env>-observability."
  value       = module.resource_groups.rg_observability_name
}

output "rg_observability_id" {
  description = "Resource ID of rg-<env>-observability."
  value       = module.resource_groups.rg_observability_id
}

output "rg_observability_location" {
  description = "Azure region of rg-<env>-observability."
  value       = module.resource_groups.rg_observability_location
}

# ---- Convenience map -------------------------------------------------------

output "resource_groups" {
  description = "Map of purpose => { name, id, location } for every RG."
  value       = module.resource_groups.resource_groups
}
