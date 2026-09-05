# envs/dev/01-resource-groups/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the resource-groups root
# config. Kept identical to bootstrap-backend/versions.tf so `.terraform.lock.hcl`
# files line up across the estate.
#
# This root only calls the `../../../modules/resource-groups/` child module,
# which itself uses only azurerm. azurecaf and azapi are NOT declared here
# because they are not used by this root — keep the provider set minimal so
# `terraform init` is fast and predictable.
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
