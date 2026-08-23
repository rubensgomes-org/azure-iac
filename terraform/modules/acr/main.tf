# modules/acr/main.tf
# -----------------------------------------------------------------------------
# Provisions one Azure Container Registry per env plus the RBAC grant that
# lets the shared UAMI pull images. Consumers:
#   - Container Apps (module 11) — pull via `registries { server, identity
#     = <shared-uami-id> }`. No admin user, no docker credentials.
#
# The passwordless model means we NEVER enable `admin_enabled`. That flag
# creates a username/password pair for the registry — the opposite of the
# design.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# SKU + posture (locals)
# -----------------------------------------------------------------------------
# - `Basic` SKU: cheapest tier and enough for a playground.
#     Standard = 100 GiB included storage (Basic = 10) + higher throughput.
#     Premium = private endpoints, geo-replication, customer-managed keys,
#               content trust, tokens/scope maps.
#   Managed-identity pull works on ALL SKUs, so Basic is the right default.
#   Upgrade to Premium is a one-line change here if we later add a PE
#   against `privatelink.azurecr.io` (zone already provisioned in module 02).
#
# - `admin_enabled = false`: no username/password — passwordless via UAMI.
#
# - `public_network_access_enabled = true`: needed for playground until
#   we move to Premium + PE. RBAC is the auth gate.
#
# - `anonymous_pull_enabled` and export policy stay at azurerm defaults
#   (both effectively disabled) — safe.
locals {
  sku                           = "Basic"
  admin_enabled                 = false
  public_network_access_enabled = true
}

# -----------------------------------------------------------------------------
# Random suffix (global uniqueness + soft-delete-safe reprovision)
# -----------------------------------------------------------------------------
# ACR names must be alphanumeric ONLY (no dashes, no underscores), 5-50
# chars, and globally unique. Basic SKU has no soft-delete concept, so the
# random is purely for collision avoidance across tenants. `keepers` locks
# the suffix to `env` — a rename regenerates.
resource "random_id" "suffix" {
  byte_length = 2 # 4 lowercase hex chars

  keepers = {
    env = var.env
  }
}

# -----------------------------------------------------------------------------
# Azure Container Registry
# -----------------------------------------------------------------------------
# Name pattern: acr<env><random> (e.g. "acrdeva7f2"). Total length with a
# 10-char env cap + "acr" + 4-char random = ≤ 17 chars, well under the
# 50-char ceiling.
resource "azurerm_container_registry" "this" {
  name                = "acr${var.env}${random_id.suffix.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku                           = local.sku
  admin_enabled                 = local.admin_enabled
  public_network_access_enabled = local.public_network_access_enabled

  tags = merge(
    var.tags,
    { component = "acr" },
  )
}

# -----------------------------------------------------------------------------
# RBAC — AcrPull for the shared UAMI
# -----------------------------------------------------------------------------
# `AcrPull` lets a caller pull (but not push) images from the registry.
# Push happens from CI or `docker push` with an ad-hoc token — never from
# apps at runtime, so the shared UAMI does NOT get AcrPush.
#
# `principal_type = "ServicePrincipal"` avoids a slow Entra lookup on every
# plan — UAMIs surface as service principals. Skipping this makes Terraform
# infer the type, which occasionally fails on brand-new identities (Entra
# hasn't propagated yet).
resource "azurerm_role_assignment" "uami_acrpull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = var.uami_principal_id
  principal_type       = "ServicePrincipal"
}
