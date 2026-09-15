# modules/service-bus/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares Terraform CLI and provider version constraints for the service-bus
# child module. Child modules declare providers they USE via
# `required_providers`, but they do NOT configure providers — the root config
# that calls this module is responsible for provider configuration.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    # azurerm covers the Service Bus namespace, queues, and the two RBAC
    # role assignments (`Azure Service Bus Data Sender` + `Data Receiver`).
    # Service Bus has no data-plane bootstrapping issue like Storage — the
    # namespace and queues are pure ARM control-plane resources.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}
