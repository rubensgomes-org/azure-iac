# modules/networking/main.tf
# -----------------------------------------------------------------------------
# Provisions the network plane for the env: one VNet, three subnets, three
# NSGs (one per subnet), and five private DNS zones linked to the VNet.
#
# The subnet set and the DNS zone set are BOTH fixed on purpose — every
# downstream module reads them by key via `data.terraform_remote_state`.
# See docs/PROVISIONING_PLAN.md §4 for the full consumption map.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Address plan and subnet topology (locals)
# -----------------------------------------------------------------------------
# One /16 VNet split into:
#   - snet-<env>-app: /23 — Container App Environment (delegated).
#       /23 is the minimum CAE Consumption plan will accept; smaller
#       fails at CAE creation time with a cryptic API error.
#   - snet-<env>-pg:  /24 — PostgreSQL Flexible Server (delegated).
#   - snet-<env>-pe:  /24 — Private endpoints for KV, Blob, ACR, Service Bus.
#
# CIDRs are non-overlapping and leave ~250 addresses of headroom in the /16
# for future subnets (jumpbox, APIM, additional PE subnet, etc.).
locals {
  vnet_cidr = "10.0.0.0/16"

  # Per-subnet config. `delegation` is a list so we can iterate it with
  # `dynamic`; an empty list means "no delegation". Every subnet in this map
  # gets a matching NSG created and associated below.
  subnets = {
    app = {
      cidr = "10.0.0.0/23"
      delegation = [{
        # A delegation "name" is a caller-chosen label; convention is to use
        # the delegated service's namespace with `/` swapped for `.`.
        name                       = "Microsoft.App.environments"
        service_delegation_name    = "Microsoft.App/environments"
        service_delegation_actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }]
    }
    pg = {
      cidr = "10.0.4.0/24"
      delegation = [{
        name                       = "Microsoft.DBforPostgreSQL.flexibleServers"
        service_delegation_name    = "Microsoft.DBforPostgreSQL/flexibleServers"
        service_delegation_actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }]
    }
    pe = {
      cidr       = "10.0.5.0/24"
      delegation = []
    }
  }

  # Fixed set of private DNS zones — one per downstream service that we
  # will reach through a private endpoint.
  #
  # Key = short service label used in outputs (dns_zone_<key>_id) and in the
  # VNet-link name. Value = the Azure-standard zone name; do NOT invent your
  # own — the service provider auto-registers records against these exact
  # names during private-endpoint creation.
  #
  # PG uses `private.postgres.database.azure.com` because PG Flexible Server
  # follows the older `private.*` naming, not the newer `privatelink.*`
  # pattern used by every other service here.
  private_dns_zones = {
    kv   = "privatelink.vaultcore.azure.net"
    blob = "privatelink.blob.core.windows.net"
    acr  = "privatelink.azurecr.io"
    sb   = "privatelink.servicebus.windows.net"
    pg   = "private.postgres.database.azure.com"
  }
}

# -----------------------------------------------------------------------------
# Virtual Network
# -----------------------------------------------------------------------------
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [local.vnet_cidr]

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------
# One instance per entry in `local.subnets`. `for_each` on a map means each
# subnet is addressable as `azurerm_subnet.this["app"]` etc., which keeps
# outputs.tf simple and lets downstream modules request subnets by key.
#
# `private_endpoint_network_policies = "Disabled"` on the `pe` subnet lets us
# create private endpoints there. Other subnets keep the default policy so
# NSG rules apply as expected.
resource "azurerm_subnet" "this" {
  for_each = local.subnets

  name                 = "snet-${var.env}-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]

  private_endpoint_network_policies = each.key == "pe" ? "Disabled" : "Enabled"

  dynamic "delegation" {
    for_each = each.value.delegation
    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service_delegation_name
        actions = delegation.value.service_delegation_actions
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Network Security Groups
# -----------------------------------------------------------------------------
# One NSG per subnet, associated. No custom rules — Azure's built-in default
# rules already:
#   - allow VNet-internal traffic in both directions
#   - allow outbound Internet
#   - deny inbound Internet
# That's the playground posture we want. Add specific rules later when a
# service needs one (e.g. bastion inbound on TCP 22).
resource "azurerm_network_security_group" "this" {
  for_each = local.subnets

  name                = "nsg-${var.env}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = local.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# -----------------------------------------------------------------------------
# Private DNS zones
# -----------------------------------------------------------------------------
# One zone per downstream service (see `local.private_dns_zones`). Each zone
# is linked to the VNet with registration disabled — the private-endpoint
# service registers A records into the zone during endpoint creation; the
# VNet does NOT auto-register VM hostnames.
resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.private_dns_zones

  name                  = "vnet-link-${var.env}-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false

  tags = var.tags
}
