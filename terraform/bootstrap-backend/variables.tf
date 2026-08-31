# bootstrap-backend/variables.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares the input variables consumed by the "bootstrap-backend" module.
# Each variable pairs a `type` (Terraform validates the value against this at
# plan time) with a human-readable `description` (surfaced by
# `terraform plan`, `terraform console`, IDE tooling, and generated docs).
#
# Concrete values for these variables live in `terraform.tfvars` (auto-loaded)
# or may be overridden on the command line via `-var`, `-var-file`, or via
# `TF_VAR_<name>` environment variables. See terraform.tfvars for the current
# precedence chain.
#
# Note: three of the identifiers below (`backend_resource_group_name`,
# `storage_account_id`, `container_name`) are ALSO hardcoded in backend.tf,
# because Terraform backend blocks cannot interpolate variables. Changing a
# value here requires the same change in backend.tf and terraform.tfvars.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# location
# -----------------------------------------------------------------------------
# Azure region into which the backend Resource Group and Storage Account are
# deployed. Any public Azure region string is accepted (e.g. "eastus",
# "westeurope", "southeastasia"). Determines:
#   - Data residency of the state blob.
#   - Network latency for every `terraform plan/apply` that reads state.
#   - Pricing tier for the Storage Account.
# Default `centralus` matches the estate region set in
# `terraform/envs/dev/env.tfvars`, so a bare `terraform apply` with no tfvars
# lands the backend in the same region as the resources it tracks.
variable "location" {
  type        = string
  description = "Azure region for the backend resources."
  default     = "centralus"
}

# -----------------------------------------------------------------------------
# backend_resource_group_name
# -----------------------------------------------------------------------------
# Name of the Resource Group that will hold every resource this module
# creates (Storage Account, RBAC assignment, and the optional
# `CanNotDelete` management lock).
#
# Azure RG naming rules: 1-90 chars; letters, digits, `-`, `_`, `.`, and
# parentheses; cannot end with a period. This module does not enforce
# those with a `validation` block - Azure rejects invalid names at apply.
#
# MUST match `resource_group_name` in backend.tf.
variable "backend_resource_group_name" {
  type        = string
  description = "Resource group that holds the Terraform remote state backend."
  default     = "rg-tfstate"
}

# -----------------------------------------------------------------------------
# storage_account_id
# -----------------------------------------------------------------------------
# Name of the Storage Account that stores state blobs. The variable is
# called `storage_account_id` (not `_name`) for historical reasons; the
# value is the Storage Account NAME.
#
# Azure Storage Account naming rules (globally unique, so a collision here
# fails apply):
#   - 3 to 24 characters,
#   - lowercase letters and digits only,
#   - no dashes, underscores, or uppercase.
# The `validation` block below enforces those rules at plan time so the
# user sees a helpful error instead of an ARM 400 response.
#
# No default is set: this must be globally unique, so every deployment
# picks its own. Must match `storage_account_name` in backend.tf.
variable "storage_account_id" {
  type        = string
  description = "Deterministic storage account id for Terraform state. Must be globally unique, lowercase alphanumeric."

  # Fail fast at `terraform plan` if the name is malformed. The regex is
  # anchored (^ ... $) so the entire string must match; `can(regex(...))`
  # returns true only when the match succeeds.
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_id))
    error_message = "storage_account_id must be 3-24 chars, lowercase letters and digits only."
  }
}

# -----------------------------------------------------------------------------
# container_name
# -----------------------------------------------------------------------------
# Name of the blob container inside the Storage Account that holds the
# `.tfstate` blobs for every module in this repo. Modules distinguish
# themselves via the backend `key`, not by using different containers
# (see backend.tf).
#
# Azure container naming rules: 3-63 chars; lowercase letters, digits,
# and single hyphens (no leading/trailing/double hyphens). Not enforced
# by a `validation` block; Azure rejects invalid names at apply.
#
# MUST match `container_name` in backend.tf.
variable "container_name" {
  type        = string
  description = "Blob container name for Terraform state."
  default     = "tfstate"
}

# -----------------------------------------------------------------------------
# replication_type
# -----------------------------------------------------------------------------
# Storage Account replication SKU. Common values:
#   - LRS   - 3 copies inside one datacentre (cheapest, no DR).
#   - ZRS   - 3 copies across availability zones in one region.
#   - GRS   - LRS + async replica to the paired region.
#   - RAGRS - GRS with read access to the secondary region.
#   - GZRS / RAGZRS - zone-redundant variants of the above.
# See terraform.tfvars for the tradeoff currently chosen and when to
# upgrade. No `validation` block: azurerm rejects unknown values on apply.
variable "replication_type" {
  type        = string
  description = "Storage replication type (LRS/GRS/RAGRS/etc.)."
  default     = "LRS"
}

# -----------------------------------------------------------------------------
# soft_delete_retention_days
# -----------------------------------------------------------------------------
# Retention window (in days) for BOTH blob soft-delete and container
# soft-delete on the state Storage Account (see the `blob_properties`
# block in main.tf). Deleted state blobs / containers can be restored
# any time inside this window.
#
# Azure accepts values 1-365. This module does not validate the range;
# an out-of-range value is rejected at apply. Higher values give more
# recovery headroom at the cost of a tiny amount of extra storage
# billing for retained tombstones.
variable "soft_delete_retention_days" {
  type        = number
  description = "Retention days for blob/container soft delete."
  default     = 7
}

# -----------------------------------------------------------------------------
# enable_rg_lock
# -----------------------------------------------------------------------------
# When `true`, main.tf creates an `azurerm_management_lock` of level
# `CanNotDelete` scoped to the backend Resource Group. That lock blocks
# deletion of the RG (and every child resource, including the Storage
# Account holding the state blob) until the lock itself is removed -
# including deletions initiated by Terraform.
#
# Set to `true` for any shared or production backend. Set to `false` for
# ephemeral / disposable environments where `terraform destroy` needs to
# succeed without manual lock removal.
variable "enable_rg_lock" {
  type        = bool
  description = "If true, applies a CanNotDelete lock to the backend RG."
  default     = true
}

# -----------------------------------------------------------------------------
# tags
# -----------------------------------------------------------------------------
# Free-form key/value tags applied to every resource this module creates
# (RG, Storage Account). Useful for cost allocation, ownership queries,
# and automated cleanup policies (e.g. Azure Policy that requires certain
# tag keys).
#
# Defaults document intent: `managedBy = "terraform"` warns humans not to
# hand-edit the resources; `purpose = "tfstate"` marks them as backend
# infrastructure; `createdBy` is the provenance key queried by tag policy (it
# duplicates `managedBy` deliberately — see the same note in
# `terraform/envs/dev/env.tfvars`); `owner` is the contact for cost and cleanup
# queries.
#
# There is deliberately NO `environment` key here, unlike the estate's tag map.
# The backend is subscription-level shared infrastructure that outlives and
# spans every environment — labelling it `dev` would be wrong, and labelling it
# with any single environment would be arbitrary.
#
# Callers can extend or replace this map entirely. Note that setting `tags` in
# `terraform.tfvars` REPLACES this default wholesale rather than merging with
# it, which would silently drop whichever keys the caller omitted — edit this
# default instead.
variable "tags" {
  type        = map(string)
  description = "Tags to apply to backend resources."
  default = {
    managedBy = "terraform"
    createdBy = "terraform"
    purpose   = "tfstate"
    owner     = "rubens.s.gomes@gmail.com"
  }
}
