# modules/resource-groups/outputs.tf
# -----------------------------------------------------------------------------
# Every downstream module consumes these values via `data.terraform_remote_state`,
# so the shape MUST stay stable. Two flavours are exposed:
#
#   1. Per-purpose flat outputs (`rg_<purpose>_name`, `rg_<purpose>_id`,
#      `rg_<purpose>_location`). Use these when a consumer wants a single
#      specific RG. Cleaner call sites, but adds ceremony to add a new
#      purpose.
#
#   2. A map output `resource_groups` keyed by purpose, with all three
#      fields per entry. Use this when a consumer iterates or when adding
#      an RG shouldn't require touching every consumer.
#
# See docs/MODULES_DEPENDENCY.md for which downstream modules read which
# outputs.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Flat per-purpose outputs
# -----------------------------------------------------------------------------
output "rg_platform_name" {
  description = "Name of the platform RG (managed identities, KV, ACR)."
  value       = azurerm_resource_group.this["platform"].name
}

output "rg_platform_id" {
  description = "Resource ID of the platform RG."
  value       = azurerm_resource_group.this["platform"].id
}

output "rg_platform_location" {
  description = "Azure region of the platform RG."
  value       = azurerm_resource_group.this["platform"].location
}

output "rg_network_name" {
  description = "Name of the network RG (VNet, NSGs, private DNS)."
  value       = azurerm_resource_group.this["network"].name
}

output "rg_network_id" {
  description = "Resource ID of the network RG."
  value       = azurerm_resource_group.this["network"].id
}

output "rg_network_location" {
  description = "Azure region of the network RG."
  value       = azurerm_resource_group.this["network"].location
}

output "rg_data_name" {
  description = "Name of the data RG (PostgreSQL, Service Bus, Storage)."
  value       = azurerm_resource_group.this["data"].name
}

output "rg_data_id" {
  description = "Resource ID of the data RG."
  value       = azurerm_resource_group.this["data"].id
}

output "rg_data_location" {
  description = "Azure region of the data RG."
  value       = azurerm_resource_group.this["data"].location
}

output "rg_app_name" {
  description = "Name of the app RG (Container App Environment, Container Apps)."
  value       = azurerm_resource_group.this["app"].name
}

output "rg_app_id" {
  description = "Resource ID of the app RG."
  value       = azurerm_resource_group.this["app"].id
}

output "rg_app_location" {
  description = "Azure region of the app RG."
  value       = azurerm_resource_group.this["app"].location
}

output "rg_observability_name" {
  description = "Name of the observability RG (Log Analytics, App Insights, Action Groups)."
  value       = azurerm_resource_group.this["observability"].name
}

output "rg_observability_id" {
  description = "Resource ID of the observability RG."
  value       = azurerm_resource_group.this["observability"].id
}

output "rg_observability_location" {
  description = "Azure region of the observability RG."
  value       = azurerm_resource_group.this["observability"].location
}

# -----------------------------------------------------------------------------
# Map output
# -----------------------------------------------------------------------------
# Convenience for consumers that would rather iterate. Keys are the purpose
# strings ("platform", "network", "data", "app", "observability"). Each value
# has `name`, `id`, and `location`.
output "resource_groups" {
  description = "Map of purpose => { name, id, location } for every RG created by this module."
  value = {
    for k, rg in azurerm_resource_group.this : k => {
      name     = rg.name
      id       = rg.id
      location = rg.location
    }
  }
}
