# envs/dev/03-log-analytics/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the log-analytics root
# config. Kept consistent with the rest of the estate.
#
# This root calls `../../../modules/log-analytics/` (azurerm + random) and
# reads state from `01-resource-groups` via `data.terraform_remote_state`
# (no extra provider needed for that).
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
