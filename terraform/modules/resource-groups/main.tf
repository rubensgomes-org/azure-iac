# modules/resource-groups/main.tf
# -----------------------------------------------------------------------------
# Creates the 5 lifecycle-aligned Resource Groups. Naming pattern:
# `rg-<env>-<purpose>`, with an optional `-<suffix>` when `rg_suffix` is set.
#
# The set of purposes is intentionally fixed — every downstream module reads
# a specific RG by name via `data.terraform_remote_state`. Adding or removing
# a purpose here is a breaking change that must be coordinated across the
# rest of the estate.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Lifecycle purposes (fixed)
# -----------------------------------------------------------------------------
# Map from purpose key (used in output names and as the `purpose` tag) to a
# short human-readable description used only for stamping into the RG's
# `purpose_description` tag.
locals {
  purposes = {
    platform      = "Managed identities, Key Vault, ACR — long-lived shared platform"
    network       = "VNet, subnets, NSGs, private DNS — long-lived network plane"
    data          = "PostgreSQL, Service Bus, Storage — stateful data plane"
    app           = "Container App Environment, Container Apps — fast-iterating runtime"
    observability = "Log Analytics, App Insights, Action Groups — orthogonal monitoring plane"
  }

  # Normalised name suffix. `var.rg_suffix` carries no separator so callers
  # cannot half-supply one ("-blue" vs "blue"); the dash is added here.
  #
  # An EMPTY value means NO suffix, which is this estate's normal mode — the
  # five RGs are `rg-dev-platform`, `rg-dev-network`, and so on. `rg_suffix`
  # exists for a parallel estate in the same subscription, not for everyday
  # use, so it defaults to empty and stays empty unless someone exports
  # `TF_VAR_rg_suffix`.
  #
  # `name` is ForceNew on azurerm_resource_group, so changing this on a LIVE
  # estate destroys and recreates all five RGs and everything in them. Three
  # consumers must agree on the empty default: this local, `var.rg_suffix`'s
  # `default`, and Make's `RG_SUFFIX` (Makefile). The workflows bind the value
  # from a repository Actions variable that resolves to "" when undefined,
  # which lands on the same unsuffixed names as a local run — that agreement
  # is the point.
  suffix = var.rg_suffix == "" ? "" : "-${var.rg_suffix}"
}

# -----------------------------------------------------------------------------
# Resource Groups
# -----------------------------------------------------------------------------
# One RG per purpose. `for_each` over the map so each RG becomes an addressable
# resource instance (`azurerm_resource_group.this["platform"]`, etc.) —
# lets outputs.tf publish per-purpose values via lookup.
#
# Tags merge the shared map from the caller with two per-RG stamps so cost
# reports and Resource Graph queries can filter by lifecycle purpose.
resource "azurerm_resource_group" "this" {
  for_each = local.purposes

  name     = "rg-${var.env}-${each.key}${local.suffix}"
  location = var.location

  tags = merge(
    var.tags,
    {
      purpose             = each.key
      purpose_description = each.value
    },
  )
}
