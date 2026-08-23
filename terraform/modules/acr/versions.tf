# modules/acr/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the acr child
# module. Child modules declare providers they USE via `required_providers`,
# but they do NOT configure providers (no `provider "x" {}` blocks) — the
# root config that calls this module is responsible for provider
# configuration.
#
# See docs/PROVISIONING_PLAN.md §5 for the standard scaffolding across every
# module.
# -----------------------------------------------------------------------------

terraform {
  required_version = "~> 1.15"

  required_providers {
    # azurerm covers the registry and the AcrPull role assignment.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }

    # `random_id` produces a 4-hex-char suffix baked into the registry
    # name. ACR names are GLOBALLY unique (across every Azure tenant) and
    # must be alphanumeric-only — random makes collision-safe naming
    # trivial and lets a destroy+recreate land on a fresh name.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
