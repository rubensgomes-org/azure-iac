# envs/dev/09-postgresql/variables.tf
# -----------------------------------------------------------------------------
# Root variables. Values come from `../env.tfvars` (shared, passed via
# -var-file) plus `terraform.tfvars` in this directory.
#
# Every variable defined in env.tfvars is declared here — even ones this
# module does not consume — because Terraform emits a warning for each
# undeclared variable it encounters in a -var-file. Declaring them all keeps
# plan/apply output clean.
# -----------------------------------------------------------------------------

# ---- Consumed by this module -----------------------------------------------

variable "env" {
  description = "Environment name. Sourced from ../env.tfvars."
  type        = string
}

variable "location" {
  description = "Azure region for the PostgreSQL Flexible Server. Sourced from ../env.tfvars."
  type        = string
}

variable "apps" {
  description = "Microservice names. One database + one set of grants per name. Sourced from ../env.tfvars."
  type        = list(string)
  default     = []
}

variable "pg_entra_admin_group_object_id" {
  description = <<-EOT
    Object ID of the Entra ID group whose members administer the PG
    server. The Terraform SP MUST be a member so the null_resource psql
    step can obtain an AAD token and call `pgaadauth_create_principal`.
    Sourced from ../env.tfvars.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.pg_entra_admin_group_object_id))
    error_message = "pg_entra_admin_group_object_id must be a valid GUID — set it in env.tfvars before applying this module."
  }
}

variable "pg_entra_admin_group_name" {
  description = <<-EOT
    Display name of the SAME Entra group referenced by
    `pg_entra_admin_group_object_id`. Passed to the AAD administrator
    resource as `principal_name` and used as the PGUSER value in the
    psql bootstrap.

    Kept as an explicit variable (instead of looked up via
    `data.azuread_group`) because the lookup requires
    `Directory.Read.All` / `Group.Read.All` on the Terraform SP — a
    playground SP typically lacks both, and granting them needs tenant
    admin consent. Sourced from ../env.tfvars.
  EOT
  type        = string

  validation {
    condition     = var.pg_entra_admin_group_name != "REPLACE_ME" && length(var.pg_entra_admin_group_name) > 0
    error_message = "pg_entra_admin_group_name must be set to the Entra group's display name — replace the REPLACE_ME placeholder in env.tfvars."
  }
}

variable "tags" {
  description = "Common tag map. Applied to the Flexible Server. Per-run override; committed defaults live in ../tags.json."
  type        = map(string)
  default     = {}
}

# Contact stamped into the `owner` tag. Declared here — not just read from
# `../tags.json` — because Terraform silently drops `TF_VAR_*` for variables a
# module does not declare, so without this declaration `TF_VAR_owner` would be
# ignored outside bootstrap-backend. `null` rather than a literal default so an
# unset environment falls through to the committed value in `../tags.json`
# instead of shadowing it; see locals.tf for the merge.
variable "owner" {
  description = "Contact for the `owner` tag. Overrides ../tags.json when set."
  type        = string
  default     = null
}

# ---- Declared for env.tfvars parity, unused by this module -----------------

variable "prefix" {
  description = "Owner/org token. Not used here (server names use a random suffix for global uniqueness); consumed by 05-key-vault."
  type        = string
  default     = null
}

# ---- Remote-state backend coordinates -------------------------------------
# Where this root READS other roots' state from, i.e. the `config` block of
# every `data "terraform_remote_state"` below in main.tf. These are the same
# three values `../backend.hcl` supplies to `terraform init` for this root's
# OWN state -- a backend block cannot take variables, so the two are declared
# separately and MUST agree.
#
# The defaults mirror ../backend.hcl so a local run needs no extra input. CI
# runners override them with TF_VAR_backend_resource_group_name /
# TF_VAR_storage_account_id / TF_VAR_container_name, which are the same names
# terraform/INITIAL_SETUP.md already tells you to export in your shell.
#
# Deliberately NOT in ../env.tfvars: `-var-file` outranks TF_VAR_*, so a value
# there would silently defeat the CI override -- the trap env.tfvars.example
# already documents for `rg_suffix`.

variable "backend_resource_group_name" {
  description = "Resource group owning the tfstate storage account. Must match ../backend.hcl."
  type        = string
  default     = "rg-tfstate"
}

variable "storage_account_id" {
  description = "Name of the storage account holding the tfstate container. Must match ../backend.hcl."
  type        = string
  default     = "sttfstaterubens01"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_id))
    error_message = "storage_account_id must be 3-24 lowercase letters/digits."
  }
}

variable "container_name" {
  description = "Blob container holding every root's state blob. Must match ../backend.hcl."
  type        = string
  default     = "tfstate"
}
