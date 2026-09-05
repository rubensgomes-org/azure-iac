# envs/dev/04-managed-identities/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the managed-identities
# root config. Kept consistent with the rest of the estate.
#
# This root only calls `../../../modules/managed-identities/` (azurerm-only)
# and reads state from `01-resource-groups` via `data.terraform_remote_state`.
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
