# modules/networking/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs and names for every downstream module (02+ callers). Naming
# convention mirrors resource-groups: one flat output per addressable thing,
# plus convenience maps at the end.
#
# Every name in this file is a public API — do NOT rename without updating
# the root config (envs/dev/02-networking/outputs.tf) and every consumer's
# `data.terraform_remote_state` block.
# -----------------------------------------------------------------------------

# ---- Virtual network -------------------------------------------------------

output "vnet_id" {
  description = "Resource ID of vnet-<env>."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of vnet-<env>."
  value       = azurerm_virtual_network.this.name
}

output "vnet_address_space" {
  description = "Address space (CIDR list) of vnet-<env>."
  value       = azurerm_virtual_network.this.address_space
}

# ---- Subnets ---------------------------------------------------------------

output "subnet_app_id" {
  description = "Resource ID of snet-<env>-app (delegated to Container App Environment)."
  value       = azurerm_subnet.this["app"].id
}

output "subnet_pg_id" {
  description = "Resource ID of snet-<env>-pg (delegated to PostgreSQL Flexible Server)."
  value       = azurerm_subnet.this["pg"].id
}

output "subnet_pe_id" {
  description = "Resource ID of snet-<env>-pe (for private endpoints)."
  value       = azurerm_subnet.this["pe"].id
}

# ---- NSGs ------------------------------------------------------------------

output "nsg_app_id" {
  description = "Resource ID of nsg-<env>-app."
  value       = azurerm_network_security_group.this["app"].id
}

output "nsg_pg_id" {
  description = "Resource ID of nsg-<env>-pg."
  value       = azurerm_network_security_group.this["pg"].id
}

output "nsg_pe_id" {
  description = "Resource ID of nsg-<env>-pe."
  value       = azurerm_network_security_group.this["pe"].id
}

# ---- Private DNS zones -----------------------------------------------------

output "dns_zone_kv_id" {
  description = "Resource ID of privatelink.vaultcore.azure.net (Key Vault PE)."
  value       = azurerm_private_dns_zone.this["kv"].id
}

output "dns_zone_blob_id" {
  description = "Resource ID of privatelink.blob.core.windows.net (Storage Blob PE)."
  value       = azurerm_private_dns_zone.this["blob"].id
}

output "dns_zone_acr_id" {
  description = "Resource ID of privatelink.azurecr.io (ACR PE)."
  value       = azurerm_private_dns_zone.this["acr"].id
}

output "dns_zone_sb_id" {
  description = "Resource ID of privatelink.servicebus.windows.net (Service Bus PE)."
  value       = azurerm_private_dns_zone.this["sb"].id
}

output "dns_zone_pg_id" {
  description = "Resource ID of private.postgres.database.azure.com (PostgreSQL Flex)."
  value       = azurerm_private_dns_zone.this["pg"].id
}

# ---- Convenience maps ------------------------------------------------------

output "subnets" {
  description = "Map of subnet key => { id, name, cidr } for every subnet."
  value = {
    for k, s in azurerm_subnet.this : k => {
      id   = s.id
      name = s.name
      cidr = s.address_prefixes[0]
    }
  }
}

output "private_dns_zones" {
  description = "Map of service key => { name, id } for every private DNS zone."
  value = {
    for k, z in azurerm_private_dns_zone.this : k => {
      name = z.name
      id   = z.id
    }
  }
}
