# modules/container-app-environment/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Terraform CLI and provider version constraints for the
# container-app-environment child module. Child modules declare providers they
# USE via `required_providers` but do NOT configure providers — the root
# config that calls this module owns provider configuration.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    # `azurerm_container_app_environment` is an azurerm resource. No `random`
    # dependency here — the environment name is the deterministic
    # `cae-<workload>-<env>`, and Container App Environments have no
    # soft-delete recycle bin the way LAW and KV do, so the deterministic name
    # costs nothing on a rebuild either.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}
