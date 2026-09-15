# modules/log-analytics/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# SKU and retention are hard-coded in main.tf as locals — the playground has
# no reason to vary them per-environment, and every value that matters (SKU
# tier, retention window, quota) has a comment explaining the choice.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces log-rgomes-lab.
    Deterministic: this module appends no random suffix, so a rebuild inside
    the 14-day soft-delete window needs an explicit recover-or-purge (see the
    comment above the workspace in main.tf).

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
    workspace name: log-<workload>-<env>.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the workspace. Must match the location of the RG passed
    via `resource_group_name`. Single-region on purpose.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the workspace. Caller supplies
    `rg-<env>-observability` (from module 01's outputs via
    `data.terraform_remote_state`).
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to the workspace. Merged with a module-local `component`
    tag for cost / graph queries.
  EOT
  type        = map(string)
  default     = {}
}
