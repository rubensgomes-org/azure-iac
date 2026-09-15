# modules/log-analytics/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the log-analytics
# child module. Child modules declare providers they USE via
# `required_providers`, but they do NOT configure providers (no `provider "x"
# {}` blocks) — the root config that calls this module is responsible for
# provider configuration.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    # Log Analytics Workspace itself is an azurerm resource.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}
