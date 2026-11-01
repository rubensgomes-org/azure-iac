# roots/18-ai-search/providers.tf
# -----------------------------------------------------------------------------
# Provider configuration for the ai-search root config.
#
# Authentication is supplied by the ARM_* environment variables:
#   - ARM_CLIENT_ID
#   - ARM_CLIENT_SECRET
#   - ARM_TENANT_ID
#   - ARM_SUBSCRIPTION_ID
# The provider block MUST NOT reference credentials directly. See
# docs/INITIAL_SETUP.md for the one-time SP setup.
#
# `storage_use_azuread` is required because the storage account disables
# shared keys; see roots/08-storage/providers.tf.
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

provider "azapi" {}
