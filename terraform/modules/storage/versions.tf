# modules/storage/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the storage
# child module. Child modules declare providers they USE via
# `required_providers`, but they do NOT configure providers — the root config
# that calls this module is responsible for provider configuration.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    # azurerm covers the storage account and the Storage Blob Data Contributor
    # role assignment.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }

    # `azapi` creates blob containers via the ARM control plane. With
    # `shared_access_key_enabled = false`, the azurerm data-plane container
    # resource (`azurerm_storage_container`) would additionally require the
    # Terraform SP to hold `Storage Blob Data Contributor` at apply time —
    # plus a wait for RBAC to propagate. `azapi_resource` uses the same
    # ARM control plane the SP already has Contributor on (via bootstrap),
    # so containers provision immediately with no data-plane grant needed.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}
