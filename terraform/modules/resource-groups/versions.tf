# modules/resource-groups/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the
# resource-groups child module. Child modules declare providers they USE via
# `required_providers`, but they do NOT configure providers (no `provider "x"
# {}` blocks) — the root config that calls this module is responsible for
# provider configuration.
# -----------------------------------------------------------------------------

terraform {
  # Accept Terraform >= 1.16.0 and < 2.0.0. Matches every other module in
  # the repo so the same CLI works everywhere.
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    # This module only creates azurerm_resource_group resources — no
    # azurecaf name generation, no azapi escape hatch. Keep the provider
    # set minimal so `terraform init` in the root config downloads only
    # what is actually needed.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}
