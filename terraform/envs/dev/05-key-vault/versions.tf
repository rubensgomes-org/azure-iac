# envs/dev/05-key-vault/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the key-vault root
# config. Kept consistent with the rest of the estate.
#
# This root calls `../../../modules/key-vault/` (azurerm + random) and
# reads state from `01-resource-groups` and `04-managed-identities` via
# `data.terraform_remote_state`.
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
