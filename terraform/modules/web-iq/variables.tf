# modules/web-iq/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf. Type, kind and SKU are hard-coded as locals in
# main.tf.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces wiq-rgomesai-lab.
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

variable "resource_group_id" {
  description = "ID of the RG that holds the account. Caller supplies the ai RG from module 01."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource. Merged with `component = \"web-iq\"`."
  type        = map(string)
  default     = {}
}
