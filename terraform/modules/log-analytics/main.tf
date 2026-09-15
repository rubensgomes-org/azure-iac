# modules/log-analytics/main.tf
# -----------------------------------------------------------------------------
# Provisions the shared Log Analytics Workspace for the env. Downstream
# consumers: Container App Environment (module 10, streams container stdout/
# stderr here), Application Insights (module 12, workspace-based), and every
# diagnostic-settings block on every azurerm resource that emits logs.
#
# One workspace per env is deliberate — cross-service correlation via KQL is
# simpler when everything lands in the same store, and the PerGB2018 SKU has
# no per-workspace overhead beyond the data ingested.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# SKU + retention (locals)
# -----------------------------------------------------------------------------
# - PerGB2018 is the modern pay-as-you-go SKU (older SKUs are legacy).
# - 30-day retention is the minimum for PerGB2018 and enough for a playground.
#   Bumping this to 90/180/365 costs more per GB after day 30.
# - `daily_quota_gb` is intentionally NOT set. A hard quota silently STOPS
#   ingestion once hit — worse than a surprise bill for a learning env.
#   Cost control belongs in Azure Budgets / Cost Management alerts, not here.
locals {
  sku               = "PerGB2018"
  retention_in_days = 30
}

# -----------------------------------------------------------------------------
# Log Analytics Workspace
# -----------------------------------------------------------------------------
# Name is the plain CAF form `log-<workload>-<env>` — fully deterministic, no
# random suffix. An operator can derive it from env.tfvars without reading
# state, which is the whole point of adopting CAF.
#
# THE TRADE-OFF, and it is a real one: LAW names live in a soft-delete recycle
# bin per RG for 14 days after a workspace is deleted. This module used to
# append a `random_id` precisely so a destroy/recreate cycle never collided
# with its own tombstone. With a fixed name it does, and `terraform apply`
# fails with "workspace name is in soft-delete state". Recover with either:
#
#   az monitor log-analytics workspace recover  -g <rg> -n log-<workload>-<env>
#   az monitor log-analytics workspace delete   -g <rg> -n log-<workload>-<env> --force
#
# See docs/NAMING.md and docs/TEARDOWN.md — the same burden applies to Key
# Vault, whose window is 90 days.
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.workload}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku               = local.sku
  retention_in_days = local.retention_in_days

  tags = merge(
    var.tags,
    { component = "log-analytics" },
  )
}
