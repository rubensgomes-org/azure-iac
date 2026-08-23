# modules/service-bus/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the service-bus
# child module. Child modules declare providers they USE via
# `required_providers`, but they do NOT configure providers — the root config
# that calls this module is responsible for provider configuration.
#
# See docs/PROVISIONING_PLAN.md §5 for the standard scaffolding across every
# module.
# -----------------------------------------------------------------------------

terraform {
  required_version = "~> 1.15"

  required_providers {
    # azurerm covers the Service Bus namespace, queues, and the two RBAC
    # role assignments (`Azure Service Bus Data Sender` + `Data Receiver`).
    # Service Bus has no data-plane bootstrapping issue like Storage — the
    # namespace and queues are pure ARM control-plane resources.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }

    # `random_id` produces a 4-hex-char suffix baked into the namespace name.
    # Service Bus namespace names are GLOBALLY unique across every Azure
    # tenant (they resolve as `<name>.servicebus.windows.net`), so a random
    # suffix keeps collision-free naming trivial and lets a destroy+recreate
    # land on a fresh name.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
