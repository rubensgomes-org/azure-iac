# modules/monitoring/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# The module provisions:
#   - one Application Insights component (workspace-based, on the shared LAW),
#   - one Action Group with an email receiver,
#   - five diagnostic settings (KV, ACR, Storage-blob, Service Bus, PG) all
#     sinking into the same shared LAW.
#
# Every downstream resource ID is a REQUIRED input — the module refuses to
# apply against a partially-provisioned estate. If a resource doesn't exist
# yet, remove its diagnostic setting from main.tf and re-add it once module
# NN is applied.
#
# See the module README for the observability posture.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into the App Insights name
    (`appi-<env>`), the action group name (`ag-<env>-ops`), and the action
    group's `short_name` (`<env>ops`, capped at 12 chars by Azure).
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the observability RG's resources (App Insights + action
    group). Must match the location of `resource_group_name`. Diagnostic
    settings themselves have no region — they inherit their target
    resource's location.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds App Insights + the action group. Caller
    supplies `rg-<env>-observability` (from module 01's outputs via
    `data.terraform_remote_state`). Keeping observability in its own RG
    matches the plan's lifecycle partitioning — data and app RGs can
    churn without touching monitoring config.
  EOT
  type        = string
}

variable "log_analytics_workspace_id" {
  description = <<-EOT
    Full Azure Resource ID of the shared Log Analytics Workspace (module
    03). Serves two roles:
      1. Backing workspace for the workspace-based Application Insights
         component (`azurerm_application_insights.workspace_id`).
      2. Destination for every diagnostic setting in this module.
    Same LAW that already receives container stdout/stderr from module 10.
  EOT
  type        = string
}

variable "action_group_email" {
  description = <<-EOT
    Email address that receives alerts fired against the action group.
    Playground default: a single receiver named `owner`. Multiple
    receivers or additional channels (SMS, webhook, ITSM) would live in
    the action group's block in main.tf — extend there when the ops
    surface actually grows.

    Kept as an explicit input (not derived from the `owner` tag) because
    the tag holds a short username while receivers need a valid email
    format. Address is validated by a regex below.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.action_group_email))
    error_message = "action_group_email must look like an email address (has one @ and a dotted domain)."
  }
}

variable "key_vault_id" {
  description = <<-EOT
    Full Azure Resource ID of the Key Vault (module 05). Target for the
    KV diagnostic setting — captures `AuditEvent` and any future log
    categories under the `allLogs` category group, plus `AllMetrics`.
    Populates who-touched-which-secret audit trail in LAW.
  EOT
  type        = string
}

variable "acr_id" {
  description = <<-EOT
    Full Azure Resource ID of the container registry (module 06). Target
    for the ACR diagnostic setting — captures repository events (pull /
    push) and login events under `allLogs`, plus `AllMetrics`. Supply-
    chain audit trail for images consumed by module 11.
  EOT
  type        = string
}

variable "storage_account_id" {
  description = <<-EOT
    Full Azure Resource ID of the storage account (module 07). The diag
    setting attaches to `<sa_id>/blobServices/default` — NOT the account
    itself — because the interesting logs (StorageRead / StorageWrite /
    StorageDelete) only surface at the blob-services subresource. Account-
    level metrics can be added as a second setting if we later care about
    capacity / transaction counts at that scope.
  EOT
  type        = string
}

variable "service_bus_namespace_id" {
  description = <<-EOT
    Full Azure Resource ID of the Service Bus namespace (module 08).
    Target for the SB diagnostic setting — captures `OperationalLogs`,
    `RuntimeAuditLogs`, and any other category rolled into `allLogs`,
    plus `AllMetrics`. Message-plane visibility for the passwordless
    sender / receiver flows.
  EOT
  type        = string
}

variable "postgresql_server_id" {
  description = <<-EOT
    Full Azure Resource ID of the PG Flexible Server (module 09). Target
    for the PG diagnostic setting — captures `PostgreSQLLogs`,
    `PostgreSQLFlexSessions`, and the query-store category group under
    `allLogs`, plus `AllMetrics`. Slow-query / connection audit trail.
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to App Insights and the action group. Merged with a
    per-resource `component` tag. Diagnostic settings don't take tags —
    they inherit metadata from their target resource — so nothing to
    merge there.
  EOT
  type        = map(string)
  default     = {}
}
