# modules/networking/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the networking
# child module. Child modules declare providers they USE via
# `required_providers`, but they do NOT configure providers (no `provider "x"
# {}` blocks) — the root config that calls this module is responsible for
# provider configuration.
# -----------------------------------------------------------------------------

terraform {
  required_version = "~> 1.15"

  required_providers {
    # Only azurerm is used — VNet, subnets, NSGs, and Private DNS zones are
    # all first-class azurerm resources. No azurecaf naming (patterns are
    # simple enough) and no azapi escape hatch needed.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }
  }
}
