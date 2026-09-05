# modules/postgresql/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the postgresql
# child module. Child modules declare providers they USE via
# `required_providers`, but they do NOT configure providers — the root config
# that calls this module is responsible for provider configuration.
# -----------------------------------------------------------------------------

terraform {
  required_version = "~> 1.15"

  required_providers {
    # azurerm covers the Flexible Server, its AAD administrator binding, the
    # firewall rules, and one database per app in `var.apps`.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }

    # `random_id` produces a 4-hex-char suffix baked into the server name.
    # Flexible Server names must be globally unique across every Azure tenant
    # (they resolve as `<name>.postgres.database.azure.com`), and Azure keeps
    # a soft-delete tombstone on the name for up to 7 days after drop — a
    # random suffix keyed on `env` sidesteps the reprovision block.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # `null_resource` runs the psql local-exec that registers the shared
    # UAMI as an in-DB AAD principal via `pgaadauth_create_principal` and
    # grants per-app-DB CONNECT + schema privileges.
    #
    # Why not cyrilgdn/postgresql? Its `postgresql_role` resource runs
    # `CREATE ROLE`, which in Azure Flexible Server with Entra-only auth
    # creates a role that CANNOT log in — only
    # `pgaadauth_create_principal` produces AAD-authenticated roles. There
    # is no cyrilgdn resource that wraps that stored procedure, so the
    # AAD-principal step is authored via null_resource + psql instead.
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
