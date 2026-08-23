# modules/networking/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# The address plan (VNet CIDR, per-subnet CIDRs) and the set of private DNS
# zones are HARD-CODED in main.tf as locals — same design choice as the
# resource-groups module. Every downstream module addresses subnets and zones
# by fixed key (`app`, `pg`, `pe`, `kv`, `blob`, `acr`, `sb`, `pg`), so making
# them variables buys no flexibility and risks drift between environments.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into every resource name:
    vnet-<env>, snet-<env>-<purpose>, nsg-<env>-<purpose>,
    vnet-link-<env>-<zone-key>.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for every network resource. Must match the location of the
    resource group passed via `resource_group_name`. Single-region on purpose.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds every resource this module creates. The caller
    supplies `rg-<env>-network` (from module 01's outputs via
    `data.terraform_remote_state`).
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to every resource in this module (VNet, subnets' parent NSGs,
    private DNS zones, and VNet links). Subnets themselves do not support
    tags in azurerm — they inherit categorisation via the VNet's tag map.
  EOT
  type        = map(string)
  default     = {}
}
