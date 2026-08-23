# bootstrap-backend/terraform.tfvars
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Concrete values for the input variables declared in variables.tf. Terraform
# auto-loads any file named `terraform.tfvars` (or `*.auto.tfvars`) in the
# working directory at plan/apply time, so no `-var-file` flag is needed.
#
# Precedence, lowest to highest:
#   1. `default` in variables.tf
#   2. `terraform.tfvars` / `*.auto.tfvars` (this file)
#   3. `-var-file=...` flags
#   4. `-var 'name=value'` flags
#   5. `TF_VAR_<name>` environment variables
#
# This file is committed to source control and holds NON-SECRET values only.
# Anything sensitive (credentials, subscription IDs) must come from the
# ARM_* environment variables consumed by the azurerm provider/backend.
#
# -----------------------------------------------------------------------------
# Keep in sync with backend.tf
# -----------------------------------------------------------------------------
# The `azurerm` backend block in backend.tf cannot reference variables, so
# the three identifiers below (`backend_resource_group_name`,
# `storage_account_id`, `container_name`) MUST match the literals hardcoded
# there. Change one, change all four.
# -----------------------------------------------------------------------------

# Azure region for the Resource Group and Storage Account. Any region works;
# `eastus` is chosen for low latency from the maintainer's location and
# broad service availability. Also drives data-residency for the state blob.
location = "eastus"

# Resource Group that will hold every backend resource created by this
# module (Storage Account, RBAC assignment, optional lock). Must match
# `resource_group_name` in backend.tf.
backend_resource_group_name = "rg-tfstate"

# Storage Account name. Azure requires this to be:
#   - globally unique across ALL Azure tenants,
#   - 3-24 characters,
#   - lowercase letters and digits only (no dashes, no underscores).
# Enforced by the `validation` block on `storage_account_id` in variables.tf.
# Must match `storage_account_name` in backend.tf.
storage_account_id = "sttfstaterubens01"

# Blob container that holds the state files for every module in this repo.
# Individual modules distinguish themselves via the backend `key` (see the
# `key` comment in backend.tf). Must match `container_name` in backend.tf.
container_name = "tfstate"

# Replication SKU for the state Storage Account.
#   - LRS   (Locally Redundant Storage)     - 3 copies in one datacentre;
#                                             cheapest; no zone/region DR.
#   - ZRS   - 3 copies across 3 AZs in one region.
#   - GRS   - LRS + async replica to a paired region.
#   - RAGRS - GRS + read access to the secondary.
# LRS is deliberate here: this is a personal/dev backend where cost matters
# more than cross-region durability. For a production, multi-team estate
# consider GRS or RAGRS so a regional outage does not brick every apply.
replication_type = "LRS"

# Soft-delete retention window (days) for both blobs and containers on the
# state Storage Account. If someone (or a broken pipeline) deletes the
# state blob, it can be restored within this window. Azure allows 1-365.
# 2 days is set to minimise cost on a disposable account; production
# should raise this to 30+ to give real recovery headroom.
soft_delete_retention_days = 2

# When true, applies a `CanNotDelete` management lock to the backend RG so
# neither Terraform nor a human can accidentally destroy the state
# infrastructure. Disabled here because this environment is intentionally
# ephemeral - toggling the lock off keeps `terraform destroy` friction-free
# for tear-down/rebuild cycles. FLIP TO `true` FOR ANY SHARED OR
# PRODUCTION BACKEND.
enable_rg_lock = false
