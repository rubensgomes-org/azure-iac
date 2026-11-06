# roots/20-language/main.tf
# -----------------------------------------------------------------------------
# Calls the language child module. This root reads two upstream states:
#   - 01-resource-groups → ai RG name (where the resource lives)
#   - 04-managed-identities → shared UAMI principal_id (target of the
#     "Cognitive Services User" grant)
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map.
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

module "language" {
  source = "../../modules/language"

  workload            = var.workload
  env                 = var.env
  location            = coalesce(var.foundry_location, var.location)
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_ai_name
  uami_principal_id   = data.terraform_remote_state.managed_identities.outputs.uami_app_principal_id
  tags                = local.tags
}
