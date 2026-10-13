# roots/14-app-gateway/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the app-gateway root
# config. Kept consistent with the rest of the estate.
#
# This root calls `../../modules/app-gateway/` (azurerm only) and reads state
# from 01, 02, 11 and 12 via `data.terraform_remote_state`.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
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
