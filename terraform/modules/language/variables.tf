# modules/language/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf. Kind, SKU and the role ID are hard-coded as
# locals in main.tf.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces lang-rgomesai-lab-<region>.
    `name` is ForceNew, so changing this on a live estate is a
    destroy+recreate. See docs/NAMING.md.
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
  description = "Azure region for the resource, and the resource name suffix."
  type        = string
}

variable "resource_group_name" {
  description = "RG that holds the resource. Caller supplies the ai RG from module 01."
  type        = string
}

variable "uami_principal_id" {
  description = "Entra object ID of the shared UAMI (module 04), granted \"Cognitive Services User\" on the resource."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource. Merged with `component = \"language\"`."
  type        = map(string)
  default     = {}
}
