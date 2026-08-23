# envs/dev/10-container-app-environment/providers.tf
# -----------------------------------------------------------------------------
# Provider configuration for the container-app-environment root config.
#
# Authentication is supplied by the ARM_* environment variables:
#   - ARM_CLIENT_ID
#   - ARM_CLIENT_SECRET
#   - ARM_TENANT_ID
#   - ARM_SUBSCRIPTION_ID
# The provider block MUST NOT reference credentials directly. See
# terraform/INITIAL_SETUP.md for the one-time SP setup that produces those
# values.
#
# The empty `features {}` block is REQUIRED by azurerm 4.x.
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
}
