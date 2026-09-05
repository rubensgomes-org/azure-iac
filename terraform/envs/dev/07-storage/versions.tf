# envs/dev/07-storage/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the storage root config.
# Kept consistent with the rest of the estate.
#
# This root calls `../../../modules/storage/` (azurerm + random + azapi) and
# reads state from `01-resource-groups` and `04-managed-identities` via
# `data.terraform_remote_state`.
#
# `time` is only used in this root (not the child module) — it drives a
# `time_sleep` that lets the RBAC grant to the Terraform SP propagate
# before the SA is created. See main.tf for the rationale.
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
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}
