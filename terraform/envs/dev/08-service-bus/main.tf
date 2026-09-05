# envs/dev/08-service-bus/main.tf
# -----------------------------------------------------------------------------
# Calls the service-bus child module. This root reads two upstream states:
#   - 01-resource-groups → data RG name (where the namespace lives)
#   - 04-managed-identities → shared UAMI principal_id (target of the two
#     RBAC grants: Data Sender + Data Receiver)
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map.
# Apps send and receive via the shared UAMI.
#
# Module 05 (key-vault) reads like a dependency but is not consumed
# here — there is no customer-managed key for encryption-at-rest in this
# iteration, and there are no SAS keys to stash (apps auth via AAD). If
# CMK is added later, wire a `data.terraform_remote_state.key_vault` block
# following the same pattern as the two below.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Remote state — module 01 (resource-groups)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "resource_groups" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "resource-groups/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Remote state — module 04 (managed-identities)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "managed_identities" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "managed-identities/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Service Bus module call
# -----------------------------------------------------------------------------
module "service_bus" {
  source = "../../../modules/service-bus"

  env                 = var.env
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_data_name
  uami_principal_id   = data.terraform_remote_state.managed_identities.outputs.uami_app_principal_id
  queues              = var.queues
  tags                = local.tags
}
