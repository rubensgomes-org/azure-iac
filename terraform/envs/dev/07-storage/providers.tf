# envs/dev/07-storage/providers.tf
# -----------------------------------------------------------------------------
# Provider configuration for the storage root config.
#
# Authentication is supplied by the ARM_* environment variables:
#   - ARM_CLIENT_ID
#   - ARM_CLIENT_SECRET
#   - ARM_TENANT_ID
#   - ARM_SUBSCRIPTION_ID
# The provider block MUST NOT reference credentials directly. See
# terraform/INITIAL_SETUP.md for the one-time SP setup.
#
# `storage_use_azuread = true` is CRITICAL for this module. Reason:
# `azurerm_storage_account` makes a post-create data-plane call to the
# blob service to poll "is this account ready?". With
# `shared_access_key_enabled = false` (the passwordless posture), the
# provider's DEFAULT key-based auth path 403s with "Key based
# authentication is not permitted on this storage account." Flipping this
# flag makes the provider use the SP's AAD token for that data-plane
# call — and the RBAC grant in main.tf (`Storage Blob Data Contributor`
# for the TF SP at the RG scope) gives that token the permissions it
# needs.
#
# The empty `features {}` block is REQUIRED by azurerm 5.x. `random`,
# `azapi`, and `time` need no explicit configuration.
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

provider "azapi" {}

provider "time" {}
