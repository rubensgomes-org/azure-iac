# modules/monitoring/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI and provider version constraints for the monitoring child
# module. Child modules declare providers they USE via `required_providers`
# but do NOT configure providers — the root config that calls this module
# owns provider configuration.
#
# Only azurerm is used: Application Insights, action groups, and diagnostic
# settings are all azurerm resources. No random suffix (the App Insights
# name is fixed `appi-<env>`; the action group name is fixed
# `ag-<env>-ops`; diagnostic settings inherit their target's uniqueness).
#
# -----------------------------------------------------------------------------

terraform {
  required_version = "~> 1.15"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }
  }
}
