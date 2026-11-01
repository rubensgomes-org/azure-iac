# roots/17-document-intelligence/main.tf
# -----------------------------------------------------------------------------
# Calls the document-intelligence child module. This root reads two upstream
# states:
#   - 01-resource-groups → ai RG name (where the resource lives)
#   - 04-managed-identities → shared UAMI principal_id (target of the
#     "Cognitive Services User" grant)
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

module "document_intelligence" {
  source = "../../modules/document-intelligence"

  workload            = var.workload
  env                 = var.env
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_ai_name
  uami_principal_id   = data.terraform_remote_state.managed_identities.outputs.uami_app_principal_id
  di_user_object_id   = var.di_user_object_id == "" ? null : var.di_user_object_id
  tags                = local.tags
}
