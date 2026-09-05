# envs/dev/06-acr/main.tf
# -----------------------------------------------------------------------------
# Calls the acr child module. This root reads two upstream states:
#   - 01-resource-groups → platform RG name (where ACR lives)
#   - 04-managed-identities → shared UAMI principal_id (target of AcrPull grant)
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map. Container
# Apps pull from this registry via the shared UAMI.
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
# ACR module call
# -----------------------------------------------------------------------------
module "acr" {
  source = "../../../modules/acr"

  acr_name            = var.acr_name
  env                 = var.env
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_platform_name
  uami_principal_id   = data.terraform_remote_state.managed_identities.outputs.uami_app_principal_id
  tags                = local.tags
}
