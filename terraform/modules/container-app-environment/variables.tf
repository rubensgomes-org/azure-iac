# modules/container-app-environment/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# Everything that could reasonably vary per-environment is a variable. Fixed
# design decisions (Consumption-only workload profile, external ingress, no
# zone redundancy) are hard-coded in main.tf with a comment explaining the
# choice — see docs/PROVISIONING_PLAN.md §4 row 10.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into the environment name
    (`cae-<env>`). Fixed name — no random suffix — because Container App
    Environments do not use a soft-delete recycle bin, so a destroy+recreate
    can reuse the same name immediately.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the environment. Must match the location of the RG
    passed via `resource_group_name` AND the region of the VNet that owns
    `infrastructure_subnet_id` — Container App Environments are strictly
    single-region and refuse cross-region subnet joins.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the environment. Caller supplies
    `rg-<env>-app` (from module 01's outputs via
    `data.terraform_remote_state`). This is the fast-iterating app RG —
    destroying the environment does not touch data-plane RGs.
  EOT
  type        = string
}

variable "log_analytics_workspace_id" {
  description = <<-EOT
    Full Azure Resource ID of the Log Analytics Workspace that receives
    container stdout/stderr. Caller supplies `law_id` from module 03's
    remote state.

    Container App Environments in azurerm 4.x accept the workspace's ARM
    resource ID directly — no shared key required. The workspace becomes
    the default `logs_destination` for every Container App in this
    environment; per-app diagnostic settings can override if needed.
  EOT
  type        = string
}

variable "infrastructure_subnet_id" {
  description = <<-EOT
    Full Azure Resource ID of the subnet that hosts the environment's
    compute plane. Caller supplies `subnet_app_id` (snet-<env>-app) from
    module 02's remote state.

    Requirements enforced by the platform (not by this module):
      - Delegated to `Microsoft.App/environments`.
      - At least a /23 for Consumption + workload profile envs; a /27 is
        the hard minimum for Consumption-only. Module 02 provisions /23.
      - Must live in the same region as `var.location`.
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to the environment. Merged with a module-local
    `component = "container-app-environment"` tag for cost / graph
    queries.
  EOT
  type        = map(string)
  default     = {}
}
