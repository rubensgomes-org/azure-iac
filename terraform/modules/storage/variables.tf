# modules/storage/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# SKU (`Standard_LRS`), kind (`StorageV2`), `shared_access_key_enabled = false`,
# and other posture flags are HARD-CODED in main.tf as locals. Bumping the
# replication tier (GRS, ZRS) or flipping shared-key auth is a deliberate
# design change — not a per-environment knob.
# -----------------------------------------------------------------------------

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces strgomesapplab.

    Storage account names allow no dashes, so the three CAF tokens run
    together; the `app` purpose is folded onto this one as elsewhere. The
    composed name is capped at 24 chars — the tightest budget in the estate —
    and main.tf asserts it in a precondition.

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
    Environment name (e.g. "lab", "dev", "prod"). Trailing token of the storage
    account name: st<workload>app<env>.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the storage account. Must match the location of the RG
    passed via `resource_group_name`.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the storage account. Caller supplies
    `rg-<env>-data` (from module 01's outputs via
    `data.terraform_remote_state`). Data RG is the right home — storage
    lifecycle is aligned with PostgreSQL and Service Bus (protected from
    `app` RG churn).
  EOT
  type        = string
}

variable "uami_principal_id" {
  description = <<-EOT
    Entra ID object ID (principal_id) of the shared UAMI created in module
    04. Used as the RBAC principal for the `Storage Blob Data Contributor`
    role assignment at storage-account scope — Container Apps use this
    identity for passwordless blob access via `DefaultAzureCredential`.
  EOT
  type        = string
}

variable "apps" {
  description = <<-EOT
    Microservice names. One blob container is created per name. Downstream
    module 11 (container-apps) can inject the matching container name into
    each app's env vars. Empty list = no containers created (SA still
    provisioned).
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.apps : can(regex("^[a-z0-9][a-z0-9-]{2,62}$", a))])
    error_message = "Each app name must be 3-63 chars, lowercase alnum + hyphens, starting with alnum (blob container naming rules)."
  }
}

variable "tags" {
  description = <<-EOT
    Tags applied to the storage account. Merged with a module-local
    `component` tag for cost / graph queries.
  EOT
  type        = map(string)
  default     = {}
}
