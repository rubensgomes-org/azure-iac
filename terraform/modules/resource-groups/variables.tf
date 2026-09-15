# modules/resource-groups/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# This module has a fixed contract: given a workload token, an environment name
# and a location, it provisions the 5 lifecycle-aligned resource groups defined
# in main.tf (`platform`, `network`, `data`, `app`, `observability`). The set of
# purposes is intentionally hard-coded there — every downstream module addresses
# them by name — so this module does not accept a "list of RGs to create" input.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`. Combined with the
    lifecycle purpose it produces rg-<workload><purpose>-<env>, e.g.
    rg-rgomesapp-lab. The purpose is folded onto this token rather than given a
    dash of its own so the name stays at three tokens (see docs/NAMING.md).

    Override it to stand a second, parallel copy of the estate alongside the
    first. Two things to know before changing it:

      - `name` is ForceNew on azurerm_resource_group. Changing this value on a
        LIVE estate plans a destroy+recreate of all five RGs, but every
        resource inside them is owned by a different state file that knows
        nothing about it — the result is a broken estate, not a rename. Set it
        at first provision, or after a full teardown.
      - Names are now deterministic estate-wide: Key Vault, Storage, Service
        Bus, Log Analytics and PostgreSQL no longer append a random suffix, and
        `acr_name` remains a fixed literal. A parallel estate therefore needs a
        different `workload` (or `env`) AND a different `acr_name`.
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
    # Lowercase alnum keeps the composed name inside the RG naming rules and
    # inside the tighter budgets downstream — the storage account name
    # (st<workload><purpose><env>, 24 chars, no dashes) is the binding one.
    # The leading letter avoids a name that looks numeric.
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.workload))
    error_message = "workload must be 2-16 lowercase alnum chars starting with a letter."
  }
}

variable "env" {
  description = <<-EOT
    Environment name (e.g. "lab", "dev", "prod"). Trailing token of every RG
    name: rg-<workload><purpose>-<env>. Also stamped into the `environment`
    tag if you override `tags` accordingly.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for every resource group in this env (e.g. "eastus",
    "westus3"). Single-region on purpose — multi-region is out of scope for
    the playground.
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to every resource group. The `purpose` tag is added on top
    of these per-RG so lifecycle categorisation is queryable in Azure
    Resource Graph / cost reports.
  EOT
  type        = map(string)
  default     = {}
}
