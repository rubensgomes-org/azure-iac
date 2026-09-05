# modules/container-apps/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI and provider version constraints for the container-apps child
# module. Child modules declare providers they USE via `required_providers`
# but do NOT configure providers — the root config that calls this module
# owns provider configuration.
#
# `azurerm_container_app` is the only resource this module manages, so
# `azurerm` is the sole dependency. No `random` needed: each app's name is a
# fixed `ca-<env>-<app>` derived from `var.apps`, and Container Apps have no
# soft-delete window on the name.
#
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
