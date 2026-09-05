# envs/dev/11-container-apps/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the container-apps root
# config. Kept consistent with the rest of the estate.
#
# This root calls `../../../modules/container-apps/` (azurerm only) and reads
# state from modules 01, 04, 06, 07, 08, 09, and 10 via
# `data.terraform_remote_state` — no extra provider needed for that.
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
