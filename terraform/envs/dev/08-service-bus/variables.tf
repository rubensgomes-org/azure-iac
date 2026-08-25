# envs/dev/08-service-bus/variables.tf
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
  description = "Azure region for the Service Bus namespace. Sourced from ../env.tfvars."
  type        = string
}

variable "tags" {
  description = "Common tag map. Applied to the Service Bus namespace. Sourced from ../env.tfvars."
  type        = map(string)
  default     = {}
}

variable "queues" {
  description = <<-EOT
    Queue names to create in the namespace. Sourced from this module's own
    terraform.tfvars (not env.tfvars) — queue topology is a service-bus
    concern, not a shared-env concern. Empty list = namespace + RBAC only.
  EOT
  type        = list(string)
  default     = []
}

# ---- Declared for env.tfvars parity, unused by this module -----------------

variable "prefix" {
  description = "Owner/org token. Not used here (Service Bus namespace names use a random suffix for global uniqueness, no prefix token); consumed by 05-key-vault."
  type        = string
  default     = null
}

variable "apps" {
  description = "Microservice names. Not used here directly — queues are decoupled from apps and driven by `var.queues` instead. Consumed by 07-storage, 09-postgresql, 11-container-apps."
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
