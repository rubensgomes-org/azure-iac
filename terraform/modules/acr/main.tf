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
# Azure Container Registry
# -----------------------------------------------------------------------------
# The name is supplied by the caller via `var.acr_name` — it is NOT derived
# from `env` and carries no random suffix. Dev uses "rubensdevacr", set in
# `terraform/envs/dev/06-acr/terraform.tfvars`.
#
# Why an explicit name instead of the `acr<env><random>` pattern the rest of
# the estate uses (kv-, st-, sb-, log-, psql-)? The registry name is the one
# name humans and CI type constantly — it is baked into every image tag, every
# `docker push`, every `az acr` invocation, and every `apps_image_map` entry.
# A random suffix makes it unmemorable and, worse, makes it CHANGE on
# destroy+recreate, silently invalidating every hardcoded reference.
#
# The trade-off accepted here: ACR names are globally unique across every
# Azure tenant, so a fixed name can be taken by someone else. There is no
# random suffix to fall back on — apply fails fast with an availability error
# rather than quietly landing on a different name. Check with
# `az acr check-name -n <name>` before adding a new env.
#
# Constraints enforced by `var.acr_name`'s validation: 5-50 chars,
# alphanumeric ONLY (no dashes, no underscores).
#
# Basic SKU has no soft-delete concept, so a destroyed name is released
# immediately and the SAME name is reusable on the next apply.
resource "azurerm_container_registry" "this" {
  name                = var.acr_name
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
