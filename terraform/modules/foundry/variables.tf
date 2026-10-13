# modules/foundry/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf. Kind, SKU and the role ID are hard-coded as
# locals in main.tf.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces aif-rgomes-lab and proj-rgomes-lab. `name` is ForceNew, so
    changing this on a live estate is a destroy+recreate. See docs/NAMING.md.
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
  description = "Environment name (e.g. \"lab\", \"dev\"). Trailing token of every name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = "Azure region for the resource and project. The Foundry resource kind must be available there."
  type        = string
}

variable "resource_group_name" {
  description = "RG that holds the Foundry resource. Caller supplies the ai RG from module 01."
  type        = string
}

variable "foundry_user_object_id" {
  description = "Entra object ID of a user granted \"Foundry User\" on the resource. Null skips the grant."
  type        = string
  default     = null

  validation {
    condition = var.foundry_user_object_id == null || can(regex(
      "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
      var.foundry_user_object_id,
    ))
    error_message = "foundry_user_object_id must be a lowercase GUID."
  }
}

variable "tags" {
  description = "Tags applied to every resource. Merged with `component = \"foundry\"`."
  type        = map(string)
  default     = {}
}
