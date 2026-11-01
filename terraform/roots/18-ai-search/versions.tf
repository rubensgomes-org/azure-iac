# roots/18-ai-search/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the ai-search
# root config. Kept consistent with the rest of the estate.
#
# This root calls `../../modules/ai-search/` and
# reads state from 01 and 04 via `data.terraform_remote_state`.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}
