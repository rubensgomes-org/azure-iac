# envs/dev/02-networking/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the networking root
# config. Kept identical to bootstrap-backend/versions.tf and
# 01-resource-groups/versions.tf so `.terraform.lock.hcl` files line up
# across the estate.
#
# This root only calls `../../../modules/networking/` (azurerm-only) and
# reads state from `../../../envs/dev/01-resource-groups/` via
# `data.terraform_remote_state`. No azurecaf or azapi needed.
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
