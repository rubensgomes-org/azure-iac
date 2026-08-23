# envs/dev/02-networking/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

# ---- Virtual network -------------------------------------------------------

output "vnet_id" {
  description = "Resource ID of vnet-<env>."
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Name of vnet-<env>."
  value       = module.networking.vnet_name
}

output "vnet_address_space" {
  description = "Address space (CIDR list) of vnet-<env>."
  value       = module.networking.vnet_address_space
}

# ---- Subnets ---------------------------------------------------------------

output "subnet_app_id" {
  description = "Resource ID of snet-<env>-app (delegated to Container App Environment)."
  value       = module.networking.subnet_app_id
}

output "subnet_pg_id" {
  description = "Resource ID of snet-<env>-pg (delegated to PostgreSQL Flexible Server)."
  value       = module.networking.subnet_pg_id
}

output "subnet_pe_id" {
  description = "Resource ID of snet-<env>-pe (for private endpoints)."
  value       = module.networking.subnet_pe_id
}

# ---- NSGs ------------------------------------------------------------------

output "nsg_app_id" {
  description = "Resource ID of nsg-<env>-app."
  value       = module.networking.nsg_app_id
}

output "nsg_pg_id" {
  description = "Resource ID of nsg-<env>-pg."
  value       = module.networking.nsg_pg_id
}

output "nsg_pe_id" {
  description = "Resource ID of nsg-<env>-pe."
  value       = module.networking.nsg_pe_id
}

# ---- Private DNS zones -----------------------------------------------------

output "dns_zone_kv_id" {
  description = "Resource ID of privatelink.vaultcore.azure.net (Key Vault PE)."
  value       = module.networking.dns_zone_kv_id
}

output "dns_zone_blob_id" {
  description = "Resource ID of privatelink.blob.core.windows.net (Storage Blob PE)."
  value       = module.networking.dns_zone_blob_id
}

output "dns_zone_acr_id" {
  description = "Resource ID of privatelink.azurecr.io (ACR PE)."
  value       = module.networking.dns_zone_acr_id
}

output "dns_zone_sb_id" {
  description = "Resource ID of privatelink.servicebus.windows.net (Service Bus PE)."
  value       = module.networking.dns_zone_sb_id
}

output "dns_zone_pg_id" {
  description = "Resource ID of private.postgres.database.azure.com (PostgreSQL Flex)."
  value       = module.networking.dns_zone_pg_id
}

# ---- Convenience maps ------------------------------------------------------

output "subnets" {
  description = "Map of subnet key => { id, name, cidr } for every subnet."
  value       = module.networking.subnets
}

output "private_dns_zones" {
  description = "Map of service key => { name, id } for every private DNS zone."
  value       = module.networking.private_dns_zones
}
