# modules/managed-identities/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the
# managed-identities child module. Child modules declare providers they USE
# via `required_providers`, but they do NOT configure providers (no
# `provider "x" {}` blocks) — the root config that calls this module is
# responsible for provider configuration.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    # Only azurerm is needed — creates one azurerm_user_assigned_identity.
    # No random suffix (UAMI names are RG-scoped, not globally unique) and
    # no azurecaf (name pattern is trivial).
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}
