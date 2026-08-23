# envs/dev/04-managed-identities/providers.tf
# -----------------------------------------------------------------------------
# Provider configuration for the managed-identities root config.
#
# Authentication is supplied by the ARM_* environment variables:
#   - ARM_CLIENT_ID
#   - ARM_CLIENT_SECRET
#   - ARM_TENANT_ID
#   - ARM_SUBSCRIPTION_ID
# The provider block MUST NOT reference credentials directly. See
# terraform/INITIAL_SETUP.md for the one-time SP setup.
#
# The empty `features {}` block is REQUIRED by azurerm 4.x.
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
}
