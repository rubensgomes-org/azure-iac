# modules/key-vault/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# The SKU, RBAC mode, and dev-friendly safety toggles (purge protection off,
# 7-day soft-delete) are HARD-CODED in main.tf as locals. Changing them at
# the module level would risk drift across environments; a prod fork of
# this module can override them there.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces kv-rgomes-lab.

    Key Vault carries the tightest budget in the estate after the storage
    account: the composed name is capped at 24 chars and there is no random
    suffix to absorb slack, so keep this short. main.tf asserts the composed
    length in a precondition.

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
    Environment name (e.g. "lab", "dev", "prod"). Trailing token of the KV
    name: kv-<workload>-<env>.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the Key Vault. Must match the location of the RG passed
    via `resource_group_name`.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the Key Vault. Caller supplies
    `rg-<env>-platform` (from module 01's outputs via
    `data.terraform_remote_state`). Platform RG is the right home — KV is
    long-lived and shared across workloads.
  EOT
  type        = string
}

variable "uami_principal_id" {
  description = <<-EOT
    Entra ID object ID (principal_id) of the shared UAMI created in module
    04. Used as the RBAC principal for the `Key Vault Secrets User` role
    assignment at vault scope.
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to the Key Vault. Merged with a module-local `component`
    tag for cost / graph queries.
  EOT
  type        = map(string)
  default     = {}
}
