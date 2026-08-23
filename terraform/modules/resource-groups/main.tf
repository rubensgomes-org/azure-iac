# modules/resource-groups/main.tf
# -----------------------------------------------------------------------------
# Creates the 5 lifecycle-aligned Resource Groups defined in
# docs/PROVISIONING_PLAN.md §3. Naming pattern: `rg-<env>-<purpose>`.
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
# `purpose_description` tag. See the PROVISIONING_PLAN for what each RG owns
# and why it is separated.
locals {
  purposes = {
    platform      = "Managed identities, Key Vault, ACR — long-lived shared platform"
    network       = "VNet, subnets, NSGs, private DNS — long-lived network plane"
    data          = "PostgreSQL, Service Bus, Storage — stateful data plane"
    app           = "Container App Environment, Container Apps — fast-iterating runtime"
    observability = "Log Analytics, App Insights, Action Groups — orthogonal monitoring plane"
  }
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

  name     = "rg-${var.env}-${each.key}"
  location = var.location

  tags = merge(
    var.tags,
    {
      purpose             = each.key
      purpose_description = each.value
    },
  )
}
