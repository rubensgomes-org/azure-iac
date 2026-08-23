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
  description = "Common tag map. Applied to the Flexible Server. Sourced from ../env.tfvars."
  type        = map(string)
  default     = {}
}

# ---- Declared for env.tfvars parity, unused by this module -----------------

variable "prefix" {
  description = "Owner/org token. Not used here (server names use a random suffix for global uniqueness); consumed by 05-key-vault."
  type        = string
  default     = null
}
