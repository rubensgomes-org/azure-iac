# modules/app-gateway/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf. SKU, autoscale bounds, ports and probe timings
# are hard-coded as locals in main.tf.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces agw-rgomes-lab and pip-rgomesagw-lab. `name` is ForceNew, so
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
  description = "Azure region. Must match the RG and the subnet's VNet."
  type        = string
}

variable "resource_group_name" {
  description = "RG that holds the gateway and public IP. Caller supplies the network RG from module 01."
  type        = string
}

variable "subnet_id" {
  description = "ID of snet-<workload>agw-<env> (module 02). Dedicated to Application Gateways."
  type        = string
}

variable "nsg_id" {
  description = "ID of nsg-<workload>agw-<env> (module 02). This module adds the gateway's inbound rules to it."
  type        = string
}

variable "dns_label" {
  description = "Public IP DNS label. The gateway answers at `<label>.<location>.cloudapp.azure.com`."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.dns_label))
    error_message = "dns_label must be 3-63 lowercase alnum/hyphen chars, starting with a letter."
  }
}

variable "public_source_cidrs" {
  description = "Source CIDRs allowed to reach the HTTP listener. Default is the whole internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.public_source_cidrs) > 0 && alltrue([for c in var.public_source_cidrs : can(cidrhost(c, 0))])
    error_message = "public_source_cidrs must be a non-empty list of valid CIDRs."
  }
}

variable "backend_ip_address" {
  description = "Container App Environment static IP (module 11). Sole backend pool member."
  type        = string
}

variable "backend_host_name" {
  description = "FQDN of the exposed Container App (module 12). Sent as Host header and SNI so the environment routes to that app."
  type        = string
  nullable    = false
}

variable "health_probe_path" {
  description = "HTTP path the gateway probes on the backend app."
  type        = string
  default     = "/health"

  validation {
    condition     = startswith(var.health_probe_path, "/")
    error_message = "health_probe_path must start with \"/\"."
  }
}

variable "tags" {
  description = "Tags applied to every resource. Merged with `component = \"app-gateway\"`."
  type        = map(string)
  default     = {}
}
