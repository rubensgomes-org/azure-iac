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

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces vnet-rgomes-lab and snet-rgomesapp-lab.

    Per-key resources (subnets, NSGs, VNet links) fold their key onto this
    token rather than adding a fourth, so the name stays at three tokens.

    `name` is ForceNew on every resource named from it, so changing this on a
    live estate is a destroy+recreate, not a rename. Set it at first provision,
    or after a full teardown. See docs/NAMING.md.
  EOT
  type        = string
  default     = "rgomes"

  # `nullable = false` is load-bearing, not decoration. Every root declares
  # `workload` with `default = null` so an env.tfvars that omits it falls
  # through to this default -- but a null passed to a nullable variable is a
  # VALUE, not an absence, so without this the fall-through hits the validation
  # below and fails with "workload must be 2-16 lowercase alnum chars" naming
  # nothing. With it, Terraform substitutes this default before validating.
  nullable = false

  validation {
    # Lowercase alnum, 2-16 chars — the same shape enforced by every module, so
    # one value can name the whole estate. The ceiling is set by the tightest
    # consumer, the storage account name (st<workload><purpose><env>, 24 chars,
    # no dashes). The leading letter avoids a name that looks numeric.
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.workload))
    error_message = "workload must be 2-16 lowercase alnum chars starting with a letter."
  }
}

variable "env" {
  description = <<-EOT
    Environment name (e.g. "lab", "dev", "prod"). Trailing token of every name
    this module creates: vnet-<workload>-<env>, snet-<workload><purpose>-<env>,
    nsg-<workload><purpose>-<env>, vnet-link-<workload><zone-key>-<env>.
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
