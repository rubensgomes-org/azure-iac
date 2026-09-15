# modules/managed-identities/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# This module has a fixed contract: create ONE User-Assigned Managed Identity
# named `id-<env>-app`. That single identity is attached to every microservice
# in the ACA environment and is the auth principal for PG, Blob, Service Bus,
# Key Vault, and ACR. Per-app identities are explicitly out of scope for this
# playground.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces id-rgomesapp-lab.
    The identity is the shared app identity, so the `app` purpose is folded
    onto this token rather than given a dash of its own.

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
    identity name: id-<workload>app-<env>.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the UAMI. Must match the location of the RG passed via
    `resource_group_name`. UAMIs are regional resources — tokens issued to
    them are valid globally, but the identity object itself lives in one
    region.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the UAMI. Caller supplies `rg-<env>-platform`
    (from module 01's outputs via `data.terraform_remote_state`). Platform
    RG is the right home because the UAMI is long-lived and shared across
    workloads.
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to the UAMI. Merged with a module-local `component` tag
    for cost / graph queries.
  EOT
  type        = map(string)
  default     = {}
}
