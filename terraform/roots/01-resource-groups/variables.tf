# roots/01-resource-groups/variables.tf
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
  description = "Azure region for every RG in this env. Sourced from ../../envs/<env>/env.tfvars."
  type        = string
}

variable "tags" {
  description = "Common tag map. Applied to every RG. Per-run override; committed defaults live in ../../envs/<env>/tags.json."
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
