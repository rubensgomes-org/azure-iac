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

variable "tags" {
  description = <<-EOT
    Tags applied to every resource group. The `purpose` tag is added on top
    of these per-RG so lifecycle categorisation is queryable in Azure
    Resource Graph / cost reports.
  EOT
  type        = map(string)
  default     = {}
}
