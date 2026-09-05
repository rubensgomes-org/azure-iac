# modules/container-app-environment/main.tf
# -----------------------------------------------------------------------------
# Provisions the Azure Container Apps Environment (ACAE / CAE) that hosts
# every microservice Container App (module 11). Wired to:
#   - The shared Log Analytics Workspace (module 03) for container logs.
#   - `snet-<env>-app` (module 02) for compute-plane VNet integration.
#
# Design decisions (all fixed here, not variables):
#
# * **Consumption-only workload profile.** No `workload_profile` block is
#   declared — in azurerm 4.x that produces a Consumption-only environment,
#   which bills per-request and needs no reserved capacity. Suits a
#   playground. Add explicit `workload_profile { workload_profile_type =
#   "D4" ... }` blocks later if a workload needs dedicated compute.
#
# * **External ingress** (`internal_load_balancer_enabled = false`). The
#   environment provisions a public static IP so the browser can hit the
#   apps. Flip to `true` for private-only ingress (requires a
#   VNet-reachable client — VPN / bastion / peered VNet).
#
# * **No zone redundancy** (`zone_redundancy_enabled = false`). Enabling it
#   requires the subnet to span all three AZs in the region, which module
#   02 does not provision today (single-AZ /23). Enabling it here without
#   fixing the subnet fails at apply time with `SubnetNotZoneRedundant`.
#
# * **Fixed name `cae-<env>`.** Container App Environments do not use a
#   soft-delete recycle bin, so `terraform destroy` frees the name for
#   immediate reuse. No random suffix needed.
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map, and the
# module README for how Container Apps (module 11) consume `cae_id`.
# -----------------------------------------------------------------------------

resource "azurerm_container_app_environment" "this" {
  name                = "cae-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Log-plane wiring. azurerm 4.x accepts the workspace ARM resource ID
  # directly (no shared-key argument needed). `logs_destination` defaults
  # to `log-analytics` when this ID is set.
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Compute-plane VNet integration. Subnet must be delegated to
  # `Microsoft.App/environments` — module 02 handles that.
  infrastructure_subnet_id = var.infrastructure_subnet_id

  # Public static IP for ingress. See file header for the flip-to-internal
  # note.
  internal_load_balancer_enabled = false

  # Zone redundancy off — subnet is not zone-redundant. See file header.
  zone_redundancy_enabled = false

  tags = merge(
    var.tags,
    { component = "container-app-environment" },
  )
}
