# modules/log-analytics/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# SKU and retention are hard-coded in main.tf as locals — the playground has
# no reason to vary them per-environment, and every value that matters (SKU
# tier, retention window, quota) has a comment explaining the choice.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into the workspace name
    (`log-<env>-<random>`) and drives the `keepers` block on the random
    suffix — changing env forces a fresh random.
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
