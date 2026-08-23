# modules/monitoring/main.tf
# -----------------------------------------------------------------------------
# Observability stack for the env. Three concerns, one module:
#
#   1. Application Insights — workspace-based, backed by the shared LAW
#      (module 03). Apps in module 11 consume
#      `APPLICATIONINSIGHTS_CONNECTION_STRING` (see `outputs.tf`) via the
#      Azure Monitor OpenTelemetry SDK. No per-app instrumentation key —
#      the connection string carries auth transparently.
#
#   2. Action Group — one receiver (email) named `owner`. Alert rules
#      (metric alerts, scheduled query alerts, activity-log alerts) are
#      NOT declared here. Ownership is deliberate: alert semantics vary
#      per workload, and wiring even a single spurious alert during
#      bring-up teaches people to mute alerts, not fix them. Add rules
#      per app in a follow-on module once real SLOs exist.
#
#   3. Diagnostic settings — five in total, one per resource that emits
#      logs worth keeping (KV, ACR, Storage-blob, Service Bus, PG). All
#      sink into the same shared LAW so a single Kusto query spans the
#      estate. See file header on each `azurerm_monitor_diagnostic_setting`
#      for the specific categories captured.
#
# Design decisions fixed here (not variables):
#
# * **Workspace-based App Insights** (`workspace_id = var.log_analytics_workspace_id`):
#   classic (non-workspace) App Insights is retired for new resources.
#   The workspace-based flavour stores telemetry in LAW tables — same
#   billing bucket as everything else and Kusto queryable alongside
#   container logs.
#
# * **`application_type = "web"`** — the general-purpose choice. Java /
#   Spring Boot apps report as `web` too; the field mainly affects the
#   Portal blade layout, not the SDK contract.
#
# * **`category_group = "allLogs"`** on every diag setting — future-proof
#   against Azure adding new log categories. Individual categories can be
#   pinned instead when we want to trim ingestion cost.
#
# * **No `sampling_percentage` / retention override on App Insights** —
#   workspace-based AI inherits both from the LAW. Set them at the
#   workspace level (module 03) if the whole estate needs to change; per-
#   AI overrides would drift the two apart.
#
# See docs/PROVISIONING_PLAN.md §4 row 12 and §9 (dev safety toggles) for
# the observability posture.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Application Insights (workspace-based)
# -----------------------------------------------------------------------------
# Fixed name `appi-<env>` — no random suffix. AI names are not globally
# unique and have no soft-delete tombstone on the name.
resource "azurerm_application_insights" "this" {
  name                = "appi-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name

  workspace_id     = var.log_analytics_workspace_id
  application_type = "web"

  tags = merge(
    var.tags,
    { component = "app-insights" },
  )
}

# -----------------------------------------------------------------------------
# Action Group — email receiver
# -----------------------------------------------------------------------------
# `short_name` is capped at 12 chars by Azure. `<env>ops` fits (`devops`,
# `prodops`, etc.) up to env="production" (8 chars + "ops" = 11).
#
# `email_receiver.use_common_alert_schema = true` opts into the current
# Azure Monitor alert payload, which is what every ITSM / webhook expects.
# Legacy schema is on its way out.
resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-${var.env}-ops"
  resource_group_name = var.resource_group_name
  short_name          = "${var.env}ops"

  email_receiver {
    name                    = "owner"
    email_address           = var.action_group_email
    use_common_alert_schema = true
  }

  tags = merge(
    var.tags,
    { component = "action-group" },
  )
}

# -----------------------------------------------------------------------------
# Diagnostic setting — Key Vault (audit trail)
# -----------------------------------------------------------------------------
# Captures `AuditEvent` (who touched which secret / key / cert) and any
# future categories Azure adds under `allLogs`. Metrics: request count,
# saturation, latency percentiles.
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-to-law"
  target_resource_id         = var.key_vault_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Diagnostic setting — Azure Container Registry
# -----------------------------------------------------------------------------
# Captures `ContainerRegistryRepositoryEvents` (pull / push) and
# `ContainerRegistryLoginEvents` under `allLogs`. Supply-chain audit for
# the images module 11 pulls via the shared UAMI.
resource "azurerm_monitor_diagnostic_setting" "acr" {
  name                       = "diag-to-law"
  target_resource_id         = var.acr_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Diagnostic setting — Storage Account (blob subresource)
# -----------------------------------------------------------------------------
# Attaches to `<sa_id>/blobServices/default` — NOT the account root. Log
# categories (StorageRead / StorageWrite / StorageDelete) only exist at
# the blob-services subresource; the top-level SA has metrics only.
# Captures every blob-plane operation, which is where the passwordless
# UAMI flows land.
resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "diag-to-law"
  target_resource_id         = "${var.storage_account_id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Diagnostic setting — Service Bus Namespace
# -----------------------------------------------------------------------------
# Captures `OperationalLogs` (send / receive / dead-letter), plus
# `RuntimeAuditLogs` and any other category rolled into `allLogs`.
# Complements the AAD-token-only auth model — every publish shows up
# with the caller's principal ID.
resource "azurerm_monitor_diagnostic_setting" "service_bus" {
  name                       = "diag-to-law"
  target_resource_id         = var.service_bus_namespace_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# -----------------------------------------------------------------------------
# Diagnostic setting — PostgreSQL Flexible Server
# -----------------------------------------------------------------------------
# Captures `PostgreSQLLogs` (server log — slow queries, errors, notices),
# `PostgreSQLFlexSessions`, and the query-store category group. Metrics:
# CPU / memory / connection counts.
resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  name                       = "diag-to-law"
  target_resource_id         = var.postgresql_server_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
