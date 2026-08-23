# modules/acr/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# SKU (`Basic`) and `admin_enabled = false` are HARD-CODED in main.tf as
# locals. Bumping to Standard/Premium is a deliberate design change (needed
# for private endpoints, geo-replication, or content trust) — not a
# per-environment knob.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into the registry name
    (`acr<env><random>`) and drives the random-suffix keeper.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the registry. Must match the location of the RG passed
    via `resource_group_name`.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the registry. Caller supplies
    `rg-<env>-platform` (from module 01's outputs via
    `data.terraform_remote_state`). Platform RG is the right home — ACR is
    long-lived and shared across workloads.
  EOT
  type        = string
}

variable "uami_principal_id" {
  description = <<-EOT
    Entra ID object ID (principal_id) of the shared UAMI created in module
    04. Used as the RBAC principal for the `AcrPull` role assignment at
    registry scope — Container Apps use this identity for passwordless
    image pulls.
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to the registry. Merged with a module-local `component`
    tag for cost / graph queries.
  EOT
  type        = map(string)
  default     = {}
}
