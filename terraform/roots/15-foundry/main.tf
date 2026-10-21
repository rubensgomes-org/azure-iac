# roots/15-foundry/main.tf
# -----------------------------------------------------------------------------
# Calls the foundry child module. This root reads three upstream states:
#   - 01-resource-groups → ai RG name (where the Foundry resource lives)
#   - 03-log-analytics → workspace ID (backs the tracing App Insights)
#   - 04-managed-identities → shared UAMI principal_id (target of the
#     "Cognitive Services OpenAI User" grant)
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

data "terraform_remote_state" "log_analytics" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "log-analytics/terraform.tfstate"
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

module "foundry" {
  source = "../../modules/foundry"

  workload                   = var.workload
  env                        = var.env
  location                   = coalesce(var.foundry_location, var.location)
  resource_group_name        = data.terraform_remote_state.resource_groups.outputs.rg_ai_name
  log_analytics_workspace_id = data.terraform_remote_state.log_analytics.outputs.law_id
  app_insights_enabled       = var.app_insights_enabled
  uami_principal_id          = data.terraform_remote_state.managed_identities.outputs.uami_app_principal_id
  # An unset Actions variable arrives as "", which means "no grant".
  foundry_user_object_id = var.foundry_user_object_id == "" ? null : var.foundry_user_object_id
  tags                   = local.tags
}
