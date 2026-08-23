# bootstrap-backend/outputs.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares the root-module outputs exposed by the "bootstrap-backend" module.
# Every `output` block below publishes a value from the state so it can be:
#
#   1. Printed on the CLI at the end of `terraform apply` (or via
#      `terraform output` / `terraform output -json`).
#   2. Consumed by shell scripts and CI pipelines - e.g. passing the storage
#      account name into an `az` command.
#   3. Read from another Terraform configuration via `terraform_remote_state`:
#
#        data "terraform_remote_state" "bootstrap" {
#          backend = "azurerm"
#          config  = { ... }
#        }
#        # data.terraform_remote_state.bootstrap.outputs.storage_account_id
#
# -----------------------------------------------------------------------------
# Why these three outputs
# -----------------------------------------------------------------------------
# They intentionally mirror the input variables of the same name so the
# apply produces a machine-readable receipt of exactly which RG, Storage
# Account, and container now hold Terraform state. Downstream modules
# configuring their own `azurerm` backend can point at these outputs
# instead of hardcoding literals.
#
# -----------------------------------------------------------------------------
# Sensitive values
# -----------------------------------------------------------------------------
# None of the values below are secrets - they are Azure resource names that
# already appear in `terraform.tfvars` and `backend.tf` (which are committed
# to source control). If a future output ever exposes a key, connection
# string, or SAS token, mark it with `sensitive = true` so Terraform
# redacts it in CLI output and prevents accidental logging.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# backend_resource_group_name
# -----------------------------------------------------------------------------
# Name of the Resource Group that owns every backend resource (Storage
# Account, RBAC assignment, optional lock). Sourced from the RG resource
# itself rather than `var.backend_resource_group_name` so the output
# reflects what Azure actually created (in case a future change adds
# name mangling, prefixes, or `azurecaf` naming).
output "backend_resource_group_name" {
  value       = azurerm_resource_group.tfstate.name
  description = "Backend RG name."
}

# -----------------------------------------------------------------------------
# storage_account_id
# -----------------------------------------------------------------------------
# Name of the Storage Account holding the tfstate blobs. Kept as the
# storage account NAME (not the full ARM resource ID) for parity with
# how `backend.tf` and downstream `az` CLI commands consume it.
# Consumers needing the full resource ID can compose it from this value
# plus the RG name and subscription, or add a second output later.
output "storage_account_id" {
  value       = azurerm_storage_account.tfstate.name
  description = "Storage account id for Terraform state."
}

# -----------------------------------------------------------------------------
# container_name
# -----------------------------------------------------------------------------
# Name of the blob container that holds every module's state blob.
# Individual modules select their own state file inside this container
# via the backend `key` (see backend.tf), so this single container name
# is enough for downstream configs to configure their own backend.
output "container_name" {
  value       = azurerm_storage_container.tfstate.name
  description = "Container name for Terraform state."
}
