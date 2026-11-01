# modules/ai-search/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf. Names and SKU are hard-coded as
# locals in main.tf.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces srch-rgomesai-lab-<region>.
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
  description = "Entra object ID of the shared UAMI (module 04), granted index read and blob contributor access."
  type        = string
}

variable "search_user_object_id" {
  description = "Entra object ID of a user granted contributor roles on the search service and storage, for portal use. Null skips the grants."
  type        = string
  default     = null

  validation {
    condition = var.search_user_object_id == null || can(regex(
      "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
      var.search_user_object_id,
    ))
    error_message = "search_user_object_id must be a lowercase GUID."
  }
}

variable "tags" {
  description = "Tags applied to every resource. Merged with `component = \"ai-search\"`."
  type        = map(string)
  default     = {}
}
