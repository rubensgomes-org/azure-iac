# modules/resource-groups/main.tf
# -----------------------------------------------------------------------------
# Creates the 5 lifecycle-aligned Resource Groups.
#
# Naming follows the Microsoft Cloud Adoption Framework (CAF) form
# `<resource type>-<workload>-<environment>`, e.g. `rg-rgomesapp-lab`. The
# lifecycle purpose is folded onto the workload token rather than given a
# dash of its own (`rgomesapp`, not `rgomes-app`) so every name in the estate
# stays at exactly three tokens — see docs/NAMING.md.
#
# The set of purposes is intentionally fixed — every downstream module reads
# a specific RG by name via `data.terraform_remote_state`. Adding or removing
# a purpose here is a breaking change that must be coordinated across the
# rest of the estate.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Lifecycle purposes (fixed)
# -----------------------------------------------------------------------------
# Map from purpose key to a short human-readable description. The key does
# double duty: it is the token appended to `workload` in the RG name, and it
# is stamped into the `purpose` tag; the value is stamped into
# `purpose_description`.
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
# `name` is ForceNew. Changing `workload` or `env` on a LIVE estate plans a
# destroy+recreate of all five RGs, but every resource inside them is owned by
# a different state file that knows nothing about it — the result is a broken
# estate, not a rename. Set both at first provision, or after a full teardown.
#
# Tags merge the shared map from the caller with two per-RG stamps so cost
# reports and Resource Graph queries can filter by lifecycle purpose.
resource "azurerm_resource_group" "this" {
  for_each = local.purposes

  name     = "rg-${var.workload}${each.key}-${var.env}"
  location = var.location

  tags = merge(
    var.tags,
    {
      purpose             = each.key
      purpose_description = each.value
    },
  )
}
