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
# Random suffix (name uniqueness across destroy/recreate cycles)
# -----------------------------------------------------------------------------
# LAW names live in a 30-day soft-delete recycle bin per RG after a workspace
# is deleted. If we reprovisioned with the same fixed name inside that
# window, azurerm would fail with "workspace name is in soft-delete state".
#
# `random_id` generates a stable value that lives in state — so re-applies
# reuse the same suffix. On `terraform destroy`, state is emptied; the next
# `terraform apply` regenerates the suffix, sidestepping the recycle bin
# entirely. `keepers.env` locks the suffix to the env token — if you ever
# rename `env`, that's semantically a fresh workspace anyway.
resource "random_id" "suffix" {
  byte_length = 2 # 2 bytes → 4 lowercase hex chars (e.g. "a7f2")

  keepers = {
    env = var.env
  }
}

# -----------------------------------------------------------------------------
# Log Analytics Workspace
# -----------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.env}-${random_id.suffix.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku               = local.sku
  retention_in_days = local.retention_in_days

  tags = merge(
    var.tags,
    { component = "log-analytics" },
  )
}
