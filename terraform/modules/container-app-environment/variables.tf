# modules/container-app-environment/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# Everything that could reasonably vary per-environment is a variable. Fixed
# design decisions (Consumption-only workload profile, external ingress, no
# zone redundancy) are hard-coded in main.tf with a comment explaining the
# choice — see the module README.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces cae-rgomes-lab.
    Container App Environments have no soft-delete recycle bin, so this fixed
    name is freed for immediate reuse by `terraform destroy`.

    `name` is ForceNew on every resource named from it, so changing this on a
    live estate is a destroy+recreate, not a rename. Set it at first provision,
    or after a full teardown. See docs/NAMING.md.
  EOT
  type        = string
  default     = "rgomes"

  # `nullable = false` is load-bearing, not decoration. Every root declares
  # `workload` with `default = null` so an env.tfvars that omits it falls
  # through to this default -- but a null passed to a nullable variable is a
  # VALUE, not an absence, so without this the fall-through hits the validation
  # below and fails with "workload must be 2-16 lowercase alnum chars" naming
  # nothing. With it, Terraform substitutes this default before validating.
  nullable = false

  validation {
    # Lowercase alnum, 2-16 chars — the same shape enforced by every module, so
    # one value can name the whole estate. The ceiling is set by the tightest
    # consumer, the storage account name (st<workload><purpose><env>, 24 chars,
    # no dashes). The leading letter avoids a name that looks numeric.
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.workload))
    error_message = "workload must be 2-16 lowercase alnum chars starting with a letter."
  }
}

variable "env" {
  description = <<-EOT
    Environment name (e.g. "lab", "dev", "prod"). Trailing token of the
    environment name: cae-<workload>-<env>.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "cae_name" {
  description = <<-EOT
    Optional override for the environment's resource name. Leave unset
    (or empty) to use the default CAF name `cae-<workload>-<env>`.

    `name` is ForceNew regardless of where it comes from, so changing
    this on a live environment is a destroy+recreate, not a rename. Set
    it at first provision, or after a full teardown.
  EOT
  type        = string
  default     = null

  validation {
    # A no-op when unset: the empty-string branch lets a CI workflow bind
    # this straight from an optional, unfilled string input (which resolves
    # to "", not null) without tripping the regex.
    condition = (
      var.cae_name == null || var.cae_name == "" ||
      can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.cae_name))
    )
    error_message = "cae_name must be 2-32 chars: lowercase alnum/hyphen, starting with a letter, not ending in a hyphen."
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

    Container App Environments accept the workspace's ARM resource ID
    directly — no shared key required. The module pairs it with
    `logs_destination = "log-analytics"`, which azurerm 5.0 made mandatory
    for the ID to take effect; per-app diagnostic settings can still
    override where a Container App needs its own destination.
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
