# modules/resource-groups/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# This module has a fixed contract: given an environment name and a location,
# it provisions the 5 lifecycle-aligned resource groups defined in
# docs/PROVISIONING_PLAN.md §3 (`platform`, `network`, `data`, `app`,
# `observability`). The set of purposes is intentionally hard-coded in main.tf
# — every downstream module addresses them by name — so this module does not
# accept a "list of RGs to create" input.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into every RG name as
    rg-<env>-<purpose>. Also stamped into the `environment` tag if you
    override `tags` accordingly.
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

variable "rg_suffix" {
  description = <<-EOT
    Optional token appended to every RG name, producing
    rg-<env>-<purpose>-<suffix>. Empty string (the default) means no suffix
    and the historical rg-<env>-<purpose> names are unchanged.

    Intended for standing a second, parallel copy of the estate alongside the
    first. Two things to know before setting it:

      - `name` is ForceNew on azurerm_resource_group. Changing this value on a
        LIVE estate plans a destroy+recreate of all five RGs, but every
        resource inside them is owned by a different state file that knows
        nothing about it — the result is a broken estate, not a rename. Set it
        at first provision, or after a full teardown (PROVISIONING_PLAN §15).
      - RG names alone do not make an estate parallel-safe. KV, Storage,
        Service Bus, Log Analytics and PostgreSQL already append a
        `random_id` for global uniqueness, but `acr_name` in
        envs/<env>/06-acr/terraform.tfvars is a fixed literal and WILL collide.

    Usually supplied as the `TF_VAR_rg_suffix` environment variable rather
    than through a tfvars file — see the note in envs/<env>/01-resource-groups
    /variables.tf about `-var-file` outranking `TF_VAR_*`.
  EOT
  type        = string
  default     = ""

  validation {
    # Same shape as `env`, plus the empty string. Kept to lowercase alnum so
    # the composed name stays inside the RG naming rules and reads cleanly in
    # the portal; the leading letter avoids a name that looks numeric.
    condition     = var.rg_suffix == "" || can(regex("^[a-z][a-z0-9]{0,9}$", var.rg_suffix))
    error_message = "rg_suffix must be empty, or 1-10 lowercase alnum chars starting with a letter."
  }
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
