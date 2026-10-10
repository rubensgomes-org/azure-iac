# roots/05-app-configuration/providers.tf
# -----------------------------------------------------------------------------
# Provider configuration for the app-configuration root config.
#
# Authentication is supplied by the ARM_* environment variables:
#   - ARM_CLIENT_ID
#   - ARM_CLIENT_SECRET
#   - ARM_TENANT_ID
#   - ARM_SUBSCRIPTION_ID
# The provider block MUST NOT reference credentials directly. See
# docs/INITIAL_SETUP.md for the one-time SP setup.
#
# The empty `features {}` block is REQUIRED by azurerm 5.x. `random` needs
# no explicit configuration.
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
}
