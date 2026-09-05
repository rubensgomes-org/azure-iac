# envs/dev/02-networking/variables.tf
# -----------------------------------------------------------------------------
# Root variables. Values come from `../env.tfvars` (shared, passed via
# -var-file).
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
  description = "Azure region for every network resource. Sourced from ../env.tfvars."
  type        = string
}

variable "tags" {
  description = "Common tag map. Applied to every resource that supports tags. Per-run override; committed defaults live in ../tags.json."
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
  description = "Owner/org token. Not used here; consumed by KV/ACR/etc. modules."
  type        = string
  default     = null
}

variable "apps" {
  description = "Microservice names. Not used here; consumed by 09-postgresql and 11-container-apps."
  type        = list(string)
  default     = []
}

variable "pg_entra_admin_group_object_id" {
  description = "Entra group object ID for PG admin. Not used here; consumed by 09-postgresql."
  type        = string
  default     = null
}

variable "pg_entra_admin_group_name" {
  description = "Entra group display name for PG admin. Not used here; consumed by 09-postgresql."
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
