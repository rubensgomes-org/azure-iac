# modules/app-configuration/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf. SKU, auth mode and network posture are
# hard-coded as locals in main.tf, as in the key-vault module.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces appcs-rgomes-lab. `name` is ForceNew, so changing this on a live
    estate is a destroy+recreate. See docs/NAMING.md.
  EOT
  type        = string
  default     = "rgomes"

  # Lets a root's `workload = null` fall through to the default above.
  nullable = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.workload))
    error_message = "workload must be 2-16 lowercase alnum chars starting with a letter."
  }
}

variable "env" {
  description = "Environment name (e.g. \"lab\", \"dev\"). Trailing token of the store name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = "Azure region for the store. Must match the RG's location."
  type        = string
}

variable "resource_group_name" {
  description = "RG that holds the store. Caller supplies the platform RG from module 01."
  type        = string
}

variable "uami_principal_id" {
  description = "principal_id of the shared UAMI (module 04). Granted `App Configuration Data Reader` at store scope."
  type        = string
}

variable "tags" {
  description = "Tags applied to the store. Merged with `component = \"app-configuration\"`."
  type        = map(string)
  default     = {}
}
