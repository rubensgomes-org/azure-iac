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

    # No `random` provider. Unlike kv-/st-/sb-/log-/psql-, this module takes
    # an EXPLICIT registry name via `var.acr_name` rather than generating a
    # random suffix — see the naming rationale in main.tf.
  }
}
