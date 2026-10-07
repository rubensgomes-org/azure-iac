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
  value       = try(azurerm_resource_group.this["platform"].name, null)
}

output "rg_platform_id" {
  description = "Resource ID of the platform RG."
  value       = try(azurerm_resource_group.this["platform"].id, null)
}

output "rg_platform_location" {
  description = "Azure region of the platform RG."
  value       = try(azurerm_resource_group.this["platform"].location, null)
}

output "rg_network_name" {
  description = "Name of the network RG (VNet, NSGs, private DNS)."
  value       = try(azurerm_resource_group.this["network"].name, null)
}

output "rg_network_id" {
  description = "Resource ID of the network RG."
  value       = try(azurerm_resource_group.this["network"].id, null)
}

output "rg_network_location" {
  description = "Azure region of the network RG."
  value       = try(azurerm_resource_group.this["network"].location, null)
}

output "rg_data_name" {
  description = "Name of the data RG (PostgreSQL, Service Bus, Storage)."
  value       = try(azurerm_resource_group.this["data"].name, null)
}

output "rg_data_id" {
  description = "Resource ID of the data RG."
  value       = try(azurerm_resource_group.this["data"].id, null)
}

output "rg_data_location" {
  description = "Azure region of the data RG."
  value       = try(azurerm_resource_group.this["data"].location, null)
}

output "rg_app_name" {
  description = "Name of the app RG (Container App Environment, Container Apps)."
  value       = try(azurerm_resource_group.this["app"].name, null)
}

output "rg_app_id" {
  description = "Resource ID of the app RG."
  value       = try(azurerm_resource_group.this["app"].id, null)
}

output "rg_app_location" {
  description = "Azure region of the app RG."
  value       = try(azurerm_resource_group.this["app"].location, null)
}

output "rg_observability_name" {
  description = "Name of the observability RG (Log Analytics, App Insights, Action Groups)."
  value       = try(azurerm_resource_group.this["observability"].name, null)
}

output "rg_observability_id" {
  description = "Resource ID of the observability RG."
  value       = try(azurerm_resource_group.this["observability"].id, null)
}

output "rg_observability_location" {
  description = "Azure region of the observability RG."
  value       = try(azurerm_resource_group.this["observability"].location, null)
}

output "rg_ai_name" {
  description = "Name of the AI RG (Foundry, MCP servers, AI agents)."
  value       = try(azurerm_resource_group.this["ai"].name, null)
}

output "rg_ai_id" {
  description = "Resource ID of the AI RG."
  value       = try(azurerm_resource_group.this["ai"].id, null)
}

output "rg_ai_location" {
  description = "Azure region of the AI RG."
  value       = try(azurerm_resource_group.this["ai"].location, null)
}

# -----------------------------------------------------------------------------
# Map output
# -----------------------------------------------------------------------------
# Convenience for consumers that would rather iterate. Keys are the purpose
# strings ("platform", "network", "data", "app", "observability", "ai"). Each
# value has `name`, `id`, and `location`.
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
