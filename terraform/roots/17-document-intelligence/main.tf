# roots/17-document-intelligence/main.tf
# -----------------------------------------------------------------------------
# Calls the document-intelligence child module. This root reads two upstream
# states:
#   - 01-resource-groups → ai RG name (where the resource lives)
#   - 04-managed-identities → shared UAMI principal_id (target of the
#     "Cognitive Services User" grant)
#
# It also grants the Terraform SP blob-data access on the ai RG, which the
# provider needs to poll the training storage account; see roots/08-storage.
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

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "tf_sp_blob_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${data.terraform_remote_state.resource_groups.outputs.rg_ai_name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

# RBAC is eventually consistent; without this the storage poll can 403.
resource "time_sleep" "wait_for_rbac" {
  depends_on      = [azurerm_role_assignment.tf_sp_blob_contributor]
  create_duration = "60s"
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

  depends_on = [time_sleep.wait_for_rbac]
}
