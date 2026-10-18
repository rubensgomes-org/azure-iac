# roots/15-foundry/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the foundry root config.
# Kept consistent with the rest of the estate.
#
# This root calls `../../modules/foundry/` (azurerm only) and reads state
# from 01 via `data.terraform_remote_state`.
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
