# envs/dev/12-monitoring/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the monitoring root config.
# Kept consistent with the rest of the estate.
#
# This root calls `../../../modules/monitoring/` (azurerm only) and reads
# state from modules 01, 03, 05, 06, 07, 08, and 09 via
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
