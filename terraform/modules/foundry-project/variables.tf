# modules/foundry-project/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name, e.g. "rgomes" produces
    proj-rgomesai-lab-<region>. `name` is ForceNew, so changing this on a
    live estate is a destroy+recreate. See docs/NAMING.md.
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

variable "name_suffix" {
  description = "Appended to `<workload>ai`, e.g. \"speech\" produces proj-rgomesaispeech-lab-<region>. \"\" adds nothing."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = can(regex("^([a-z0-9]{2,16})?$", var.name_suffix))
    error_message = "name_suffix must be empty or 2-16 lowercase alnum chars."
  }
}

variable "env" {
  description = "Environment name (e.g. \"lab\", \"dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = "Azure region of the Foundry resource, and the project name suffix."
  type        = string
}

variable "foundry_id" {
  description = "Resource ID of the Foundry resource (module 15) that holds the project."
  type        = string

  validation {
    condition     = var.foundry_id != null
    error_message = "No Foundry resource in this region; run aif-create.yml first."
  }
}

variable "tags" {
  description = "Tags applied to the project. Merged with `component = \"foundry\"`."
  type        = map(string)
  default     = {}
}
