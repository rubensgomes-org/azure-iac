# roots/19-web-iq/providers.tf
# -----------------------------------------------------------------------------
# Provider configuration for the web-iq root config.
#
# Authentication is supplied by the ARM_* environment variables:
#   - ARM_CLIENT_ID
#   - ARM_CLIENT_SECRET
#   - ARM_TENANT_ID
#   - ARM_SUBSCRIPTION_ID
# The provider block MUST NOT reference credentials directly. See
# docs/INITIAL_SETUP.md for the one-time SP setup.
# -----------------------------------------------------------------------------

provider "azapi" {}
