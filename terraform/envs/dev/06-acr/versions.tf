# envs/dev/06-acr/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the acr root config.
# Kept consistent with the rest of the estate.
#
# This root calls `../../../modules/acr/` (azurerm only — the module takes an
# explicit registry name and no longer generates a random suffix) and reads state
# from `01-resource-groups` and `04-managed-identities` via
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
