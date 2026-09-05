# modules/key-vault/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the key-vault
# child module. Child modules declare providers they USE via
# `required_providers`, but they do NOT configure providers (no `provider "x"
# {}` blocks) — the root config that calls this module is responsible for
# provider configuration.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    # azurerm covers Key Vault itself, the role assignment, and the
    # azurerm_client_config data source used to read the current tenant ID.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }

    # `random_id` produces a 4-hex-char suffix baked into the KV name. Key
    # Vault names are GLOBALLY unique (across all Azure tenants), so a
    # collision-safe random is worth having. Also sidesteps the 7-day
    # soft-delete recycle bin on destroy+recreate cycles — the new random
    # produces a fresh name that isn't held by the tombstone.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
