# bootstrap-backend/main.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Core resource definitions for the "bootstrap-backend" module. This is the
# one module in the repo that provisions the Azure infrastructure used as the
# Terraform *remote state backend* for every other module.
#
# Resources created here:
#   - azurerm_resource_group.tfstate           - container for backend assets
#   - azurerm_storage_account.tfstate          - hardened Storage Account
#   - azurerm_storage_container.tfstate        - blob container for state
#   - azurerm_role_assignment.state_blob_...   - RBAC for the current caller
#   - azurerm_management_lock.tfstate_rg_lock  - optional deletion lock
#
# See backend.tf for the chicken-and-egg workflow that applies this module
# once with local state, then migrates its own state into the container it
# just created.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# azurerm provider configuration
# -----------------------------------------------------------------------------
# Version pin lives in versions.tf. Authentication is supplied by the ARM_*
# environment variables (ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID,
# ARM_SUBSCRIPTION_ID) so no credentials appear in code.
#
# The empty `features {}` block is REQUIRED by the azurerm 4.x provider even
# when no feature toggles are overridden - omitting it fails `terraform
# init`. Individual feature groups (e.g. `key_vault { purge_soft_delete_on_
# destroy = ... }`) can be added inside it as needed.
provider "azurerm" {
  features {}
}

# -----------------------------------------------------------------------------
# Current caller identity
# -----------------------------------------------------------------------------
# Returns metadata about the identity Terraform is running as (the Service
# Principal referenced by the ARM_* env vars). Used below to grant that same
# identity data-plane RBAC on the Storage Account so it can read/write the
# state blob after the account is created.
#
# In CI, the pipeline SP typically runs Terraform, so this pattern grants
# the pipeline itself the permissions it needs on its own state. For
# shared environments you may prefer to remove this and grant a dedicated
# identity out-of-band.
data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------
# Single tag map applied to every taggable resource below. `var.owner` is
# merged over `var.tags` so the per-operator contact can be overridden on its
# own (`TF_VAR_owner`) without restating the whole map — and so it wins if a
# caller happens to pass an `owner` key inside `var.tags` as well.
locals {
  tags = merge(var.tags, {
    owner = var.owner
  })
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
# Holds every resource created by this module. Name and location come from
# variables; `terraform.tfvars` sets the defaults for this deployment. Note
# that `var.backend_resource_group_name` MUST match the literal in
# backend.tf (backend blocks cannot interpolate).
resource "azurerm_resource_group" "tfstate" {
  name     = var.backend_resource_group_name
  location = var.location
  tags     = local.tags
}

# -----------------------------------------------------------------------------
# Storage Account
# -----------------------------------------------------------------------------
# The Storage Account that persists the Terraform state blobs. Several
# choices are deliberate:
#
#   - `account_tier = "Standard"`     - state blobs are tiny and infrequently
#                                       read; Premium adds no value.
#   - `account_kind = "StorageV2"`    - required for blob soft-delete,
#                                       versioning, and modern RBAC.
#   - `account_replication_type`      - LRS/GRS/... chosen via variable; see
#                                       variables.tf for the tradeoffs.
#   - `min_tls_version = "TLS1_2"`    - refuse older TLS to satisfy
#                                       common security baselines.
#   - `allow_nested_items_to_be_
#      public = false`                - block anonymous blob access at the
#                                       account level; state MUST stay
#                                       private.
#
# Name comes from `var.storage_account_id`, which is validated in
# variables.tf against Azure's 3-24 lowercase-alnum rule and MUST be
# globally unique across all Azure tenants.
resource "azurerm_storage_account" "tfstate" {
  name                     = var.storage_account_id
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"

  # -----------------------------------
  # Hardening defaults
  # -----------------------------------
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # ---------------------------------------------------------------------------
  # Blob properties - state safety net
  # ---------------------------------------------------------------------------
  # Terraform state is the single source of truth for what has been
  # provisioned; losing it means resources become orphaned in Azure and
  # unmanaged in code. The three settings below stack up defense in depth:
  #
  #   - `versioning_enabled = true` - each write to a state blob is kept as
  #     an immutable prior version, so a bad `apply` can be rolled back by
  #     promoting a previous version.
  #   - `delete_retention_policy` - deleted state blobs are recoverable for
  #     N days (soft delete) instead of vanishing immediately.
  #   - `container_delete_retention_policy` - same protection at the
  #     container level, in case the whole container is deleted.
  #
  # Retention window is variable-driven; see variables.tf for the Azure-
  # imposed 1-365 range and cost/recovery tradeoffs.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Blob container
# -----------------------------------------------------------------------------
# The container that actually holds the `.tfstate` blobs for every module in
# this repo. Modules distinguish themselves via the backend `key` (see
# backend.tf), so a single container serves the whole estate.
#
# `container_access_type = "private"` disallows anonymous access - the only
# way to read a state blob is via an authenticated request (account key,
# SAS, or AAD token). Combined with `allow_nested_items_to_be_public = false`
# on the account, this prevents any accidental public exposure of state.
resource "azurerm_storage_container" "tfstate" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# -----------------------------------------------------------------------------
# RBAC: grant the current identity data-plane access
# -----------------------------------------------------------------------------
# `Storage Blob Data Contributor` is the data-plane role that lets a
# principal read/write blob contents (as opposed to the control-plane
# `Contributor` which manages the account itself). It is required whenever
# the backend uses AAD auth (`use_azuread_auth = true` in backend.tf), and
# is a good baseline even in access-key mode so callers can inspect state
# with `az storage blob` commands.
#
# `principal_id` is the object ID of whoever ran `terraform apply`. In
# local dev this is the developer's SP; in CI it is the pipeline SP. If
# your operational model uses a separate identity for state I/O, replace
# `data.azurerm_client_config.current.object_id` with that identity's
# object ID (or delete this resource and grant the role out-of-band).
resource "azurerm_role_assignment" "state_blob_contributor" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# -----------------------------------------------------------------------------
# Optional deletion lock
# -----------------------------------------------------------------------------
# When `var.enable_rg_lock` is true, an Azure `CanNotDelete` management
# lock is placed on the backend RG. The lock is honoured by ALL callers -
# including Terraform itself - so `terraform destroy` on this module will
# fail until the lock is removed by hand.
#
# The `count` meta-argument implements the toggle: `count = 1` creates the
# resource, `count = 0` skips it entirely. References elsewhere would need
# `[0]` indexing (e.g. `azurerm_management_lock.tfstate_rg_lock[0].id`)
# because `count` turns the resource into a list.
#
# See variables.tf for guidance on when to enable this (production /
# shared) vs disable it (ephemeral / disposable environments).
resource "azurerm_management_lock" "tfstate_rg_lock" {
  count      = var.enable_rg_lock ? 1 : 0
  name       = "tfstate-can-not-delete"
  scope      = azurerm_resource_group.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Protect Terraform remote state resources."
}
