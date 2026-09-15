# roots/03-log-analytics/variables.tf
# -----------------------------------------------------------------------------
# Root variables. Values come from `../../envs/<env>/env.tfvars` (shared,
# passed via -var-file).
#
# Every variable defined in env.tfvars is declared here — even ones this
# module does not consume — because Terraform emits a warning for each
# undeclared variable it encounters in a -var-file. Declaring them all keeps
# plan/apply output clean.
# -----------------------------------------------------------------------------

# ---- Consumed by this module -----------------------------------------------

variable "env" {
  description = "Environment name. Sourced from ../../envs/<env>/env.tfvars."
  type        = string
}

# CAF workload token. Every name this estate creates is
# `<type>-<workload>-<env>`, so this value plus `env` determines the whole
# namespace — see docs/NAMING.md.
#
# `name` is ForceNew on every resource composed from it. Changing this on a
# LIVE estate is a destroy+recreate spread across twelve state files that know
# nothing about each other, which is a broken estate rather than a rename. Set
# it at first provision, or after a full teardown.
#
# `null` rather than a literal default so an unset value falls through to the
# child module's own default (`rgomes`) instead of duplicating the literal in
# twelve roots. The fall-through only works because the child declares
# `nullable = false`: a null passed to a nullable variable is a VALUE, not an
# absence, and would fail the child's validation rather than be replaced.
variable "workload" {
  description = "CAF workload token. Sourced from ../../envs/<env>/env.tfvars."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for the workspace. Sourced from ../../envs/<env>/env.tfvars."
  type        = string
}

variable "tags" {
  description = "Common tag map. Applied to the workspace. Per-run override; committed defaults live in ../../envs/<env>/tags.json."
  type        = map(string)
  default     = {}
}

# Contact stamped into the `owner` tag. Declared here — not just read from
# `../../envs/<env>/tags.json` — because Terraform silently drops `TF_VAR_*`
# for variables a module does not declare, so without this declaration
# `TF_VAR_owner` would be ignored outside bootstrap-backend. `null` rather
# than a literal default so an unset environment falls through to the
# committed value in that file instead of shadowing it; see locals.tf for the
# merge.
variable "owner" {
  description = "Contact for the `owner` tag. Overrides ../../envs/<env>/tags.json when set."
  type        = string
  default     = null
}

# ---- Declared for env.tfvars parity, unused by this module -----------------

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
# three values `../../envs/<env>/backend.hcl` supplies to `terraform init`
# for this root's OWN state -- a backend block cannot take variables, so the
# two are declared separately and MUST agree.
#
# Required, with no defaults, and that is deliberate. The roots under
# terraform/roots/ are shared by every environment, so a default here can
# only ever name one of them. While the roots lived under envs/dev/ a default
# pointing at the dev backend was merely redundant; shared, it becomes a
# silent cross-environment read -- `init` attaches to the container named by
# the environment's own backend.hcl while every remote-state read below falls
# through to the default, handing this plan another environment's RG names
# and subnet IDs. Nothing errors. The estate just comes out wired to the
# wrong place.
#
# Supply all three as TF_VAR_backend_resource_group_name /
# TF_VAR_storage_account_id / TF_VAR_container_name -- the names
# docs/INITIAL_SETUP.md already tells you to export, and the ones both CI
# workflows bind. Miss one and Terraform stops with "No value for required
# variable", naming it.
#
# Deliberately NOT in `../../envs/<env>/env.tfvars`: `-var-file` outranks
# TF_VAR_*, so a value there would silently defeat the CI override -- the
# trap env.tfvars.example documents at the top of the file. `workload` sits on
# the other side of that line, in env.tfvars, precisely because it is meant to
# be per-environment and pinned rather than overridable from the shell.

variable "backend_resource_group_name" {
  description = "Resource group owning the tfstate storage account. Must match the environment's backend.hcl."
  type        = string
}

variable "storage_account_id" {
  description = "Name of the storage account holding the tfstate container. Must match the environment's backend.hcl."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_id))
    error_message = "storage_account_id must be 3-24 lowercase letters/digits."
  }
}

variable "container_name" {
  description = "Blob container holding every root's state blob. Must match the environment's backend.hcl."
  type        = string
}
