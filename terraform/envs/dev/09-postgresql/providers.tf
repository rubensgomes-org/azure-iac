# envs/dev/09-postgresql/providers.tf
# -----------------------------------------------------------------------------
# Provider configuration for the postgresql root config.
#
# Authentication is supplied by the ARM_* environment variables:
#   - ARM_CLIENT_ID
#   - ARM_CLIENT_SECRET
#   - ARM_TENANT_ID
#   - ARM_SUBSCRIPTION_ID
# The provider block MUST NOT reference credentials directly. See
# terraform/INITIAL_SETUP.md for the one-time SP setup.
#
# `http` needs no auth — it fetches the runner's public IP from an
# unauthenticated endpoint (`https://api.ipify.org`).
#
# The empty `features {}` block is REQUIRED by azurerm 5.x.
#
# `azuread` intentionally NOT configured here. Earlier iterations of this
# module looked up the Entra admin group's display name via
# `data.azuread_group`, but that requires `Directory.Read.All` /
# `Group.Read.All` on the Terraform SP — a playground SP typically lacks
# both. The group name is now passed explicitly via
# `var.pg_entra_admin_group_name` from env.tfvars.
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
}

provider "http" {}
