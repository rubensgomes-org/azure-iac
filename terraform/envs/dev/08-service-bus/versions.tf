# envs/dev/08-service-bus/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the service-bus root config.
# Kept consistent with the rest of the estate.
#
# This root calls `../../../modules/service-bus/` (azurerm + random) and
# reads state from `01-resource-groups` and `04-managed-identities` via
# `data.terraform_remote_state`. No `azapi` and no `time` — Service Bus has
# no data-plane bootstrap issue like Storage.
# -----------------------------------------------------------------------------

terraform {
  required_version = "~> 1.15"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
