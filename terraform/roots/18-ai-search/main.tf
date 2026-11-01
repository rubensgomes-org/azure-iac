# roots/18-ai-search/main.tf
# -----------------------------------------------------------------------------
# Calls the ai-search child module. This root reads two upstream
# states:
#   - 01-resource-groups → ai RG name (where the resources live)
#   - 04-managed-identities → shared UAMI principal_id (target of the
#     search and blob grants)
#
# Root 01 grants the Terraform SP blob-data access on the ai RG, which the
# provider needs to poll the storage account.
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

module "ai_search" {
  source = "../../modules/ai-search"

  workload              = var.workload
  env                   = var.env
  location              = var.location
  resource_group_name   = data.terraform_remote_state.resource_groups.outputs.rg_ai_name
  uami_principal_id     = data.terraform_remote_state.managed_identities.outputs.uami_app_principal_id
  search_user_object_id = var.search_user_object_id == "" ? null : var.search_user_object_id
  tags                  = local.tags
}
