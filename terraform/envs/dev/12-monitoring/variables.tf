# envs/dev/12-monitoring/variables.tf
# -----------------------------------------------------------------------------
# Root variables. Values come from `../env.tfvars` (shared, passed via
# -var-file) plus this root's own `terraform.tfvars` for module-specific
# overrides (currently: the action group email receiver).
#
# Every variable defined in env.tfvars is declared here — even ones this
# module does not consume — because Terraform emits a warning for each
# undeclared variable it encounters in a -var-file. Declaring them all
# keeps plan/apply output clean.
# -----------------------------------------------------------------------------

# ---- Consumed by this module (from ../env.tfvars) --------------------------

variable "env" {
  description = "Environment name. Sourced from ../env.tfvars."
  type        = string
}

variable "location" {
  description = "Azure region for App Insights + action group. Sourced from ../env.tfvars."
  type        = string
}

variable "tags" {
  description = "Common tag map. Applied to App Insights + action group. Sourced from ../env.tfvars."
  type        = map(string)
  default     = {}
}

# ---- Consumed by this module (from terraform.tfvars) -----------------------

variable "action_group_email" {
  description = <<-EOT
    Email receiver for the `owner` alert channel. Must be a valid email
    format (validated in the child module).

    Set in this root's `terraform.tfvars` — NOT in `../env.tfvars` —
    because the address is specific to this module's use case and other
    modules would ignore it.
  EOT
  type        = string
}

# ---- Declared for env.tfvars parity, unused by this module -----------------

variable "prefix" {
  description = "Owner/org token. Not used here; consumed by KV/ACR/etc. modules."
  type        = string
  default     = null
}

variable "apps" {
  description = "Microservice names. Not used here; consumed by 07/09/11."
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
