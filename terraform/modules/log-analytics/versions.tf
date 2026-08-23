# modules/log-analytics/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the log-analytics
# child module. Child modules declare providers they USE via
# `required_providers`, but they do NOT configure providers (no `provider "x"
# {}` blocks) — the root config that calls this module is responsible for
# provider configuration.
#
# See docs/PROVISIONING_PLAN.md §5 for the standard scaffolding across every
# module.
# -----------------------------------------------------------------------------

terraform {
  required_version = "~> 1.15"

  required_providers {
    # Log Analytics Workspace itself is an azurerm resource.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }

    # `random_id` produces a 4-hex-char suffix baked into the LAW name.
    # LAW names go into a 30-day soft-delete recycle bin — a random suffix
    # lets a destroy+recreate cycle land on a fresh name without waiting
    # out the block. See docs/PROVISIONING_PLAN.md §9.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
