# envs/dev/01-resource-groups/variables.tf
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
  description = "Azure region for every RG in this env. Sourced from ../env.tfvars."
  type        = string
}

variable "tags" {
  description = "Common tag map. Applied to every RG. Sourced from ../env.tfvars."
  type        = map(string)
  default     = {}
}

# ---- Consumed by this module, sourced from the ENVIRONMENT -----------------

# Deliberately NOT in ../env.tfvars, and deliberately without a value anywhere
# on disk. It is supplied — when it is supplied at all — as an environment
# variable:
#
#   export TF_VAR_rg_suffix=blue
#   make apply-resource-groups        # -> rg-dev-platform-blue, ...
#
# Keeping it out of the tfvars files is what makes that work: `-var-file`
# OUTRANKS `TF_VAR_*` in Terraform's precedence order, so the moment
# `rg_suffix` appears in env.tfvars the environment variable is silently
# ignored. Pick one mechanism; this repo picks the environment.
#
# The other eleven module roots do not declare this and do not need to — they
# read RG names out of module 01's remote state, so the suffix reaches them
# without any code change. An undeclared TF_VAR_* is ignored without warning
# (unlike an undeclared key in a -var-file), so exporting it in the shell does
# not disturb their plans either.
#
# See modules/resource-groups/variables.tf for the ForceNew warning: this is
# safe to set at first provision or after a full teardown, NOT on a live estate.
variable "rg_suffix" {
  description = "Optional suffix appended to every RG name. Set via TF_VAR_rg_suffix, not tfvars."
  type        = string
  default     = ""
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
