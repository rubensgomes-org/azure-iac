# roots/19-web-iq/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the web-iq root config.
# Kept consistent with the rest of the estate.
#
# This root calls `../../modules/web-iq/` and reads state from 01 via
# `data.terraform_remote_state`.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}
