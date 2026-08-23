# modules/key-vault/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# The SKU, RBAC mode, and dev-friendly safety toggles (purge protection off,
# 7-day soft-delete) are HARD-CODED in main.tf as locals. Changing them at
# the module level would risk drift across environments; a prod fork of
# this module can override them there.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into the KV name
    (`kv-<env>-<prefix>-<random>`) and into the random-suffix keeper.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "prefix" {
  description = <<-EOT
    Owner/org token used to anchor globally-unique names. Baked into the KV
    name (`kv-<env>-<prefix>-<random>`) and the random-suffix keeper. Must
    be lowercase alnum; total name length (env + prefix + random + literals)
    is capped at 24 chars, so keep this short (e.g. "rubens").
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.prefix))
    error_message = "prefix must be 2-16 lowercase alnum chars starting with a letter."
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
