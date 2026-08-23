# envs/dev/08-service-bus/providers.tf
# -----------------------------------------------------------------------------
# Provider configuration for the service-bus root config.
#
# Authentication is supplied by the ARM_* environment variables:
#   - ARM_CLIENT_ID
#   - ARM_CLIENT_SECRET
#   - ARM_TENANT_ID
#   - ARM_SUBSCRIPTION_ID
# The provider block MUST NOT reference credentials directly. See
# terraform/INITIAL_SETUP.md for the one-time SP setup.
#
# Unlike 07-storage, no `storage_use_azuread` flag is needed here — Service
# Bus namespace/queue operations are pure ARM control-plane calls, so the
# Terraform SP's existing Contributor grant (via bootstrap) suffices. No
# data-plane token dance, no post-create RBAC propagation wait.
#
# The empty `features {}` block is REQUIRED by azurerm 4.x. `random` needs
# no explicit configuration.
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
}
