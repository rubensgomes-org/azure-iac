# modules/storage/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# SKU (`Standard_LRS`), kind (`StorageV2`), `shared_access_key_enabled = false`,
# and other posture flags are HARD-CODED in main.tf as locals. Bumping the
# replication tier (GRS, ZRS) or flipping shared-key auth is a deliberate
# design change — not a per-environment knob.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into the storage account
    name (`st<env>app<random>`) and drives the random-suffix keeper.
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
