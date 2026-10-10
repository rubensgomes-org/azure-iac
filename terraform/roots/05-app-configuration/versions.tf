# roots/05-app-configuration/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the app-configuration root
# config. Kept consistent with the rest of the estate.
#
# This root calls `../../modules/app-configuration/` (azurerm only) and
# reads state from `01-resource-groups` and `04-managed-identities` via
# `data.terraform_remote_state`.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}
