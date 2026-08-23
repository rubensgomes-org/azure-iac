# modules/managed-identities/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# This module has a fixed contract: create ONE User-Assigned Managed Identity
# named `id-<env>-app`. That single identity is attached to every microservice
# in the ACA environment and is the auth principal for PG, Blob, Service Bus,
# Key Vault, and ACR. Per-app identities are explicitly out of scope for this
# playground — see docs/PROVISIONING_PLAN.md §12.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into the UAMI name:
    id-<env>-app.
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
