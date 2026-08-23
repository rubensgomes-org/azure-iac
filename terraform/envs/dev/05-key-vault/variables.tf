# envs/dev/05-key-vault/variables.tf
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

variable "prefix" {
  description = "Owner/org token. Baked into the KV name. Sourced from ../env.tfvars."
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault. Sourced from ../env.tfvars."
  type        = string
}

variable "tags" {
  description = "Common tag map. Applied to the Key Vault. Sourced from ../env.tfvars."
  type        = map(string)
  default     = {}
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
