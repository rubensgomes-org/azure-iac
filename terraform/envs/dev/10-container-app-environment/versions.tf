# envs/dev/10-container-app-environment/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the
# container-app-environment root config. Kept consistent with the rest of
# the estate.
#
# This root calls `../../../modules/container-app-environment/` (azurerm
# only) and reads state from `01-resource-groups`, `02-networking`, and
# `03-log-analytics` via `data.terraform_remote_state` — no extra provider
# needed for that.
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
