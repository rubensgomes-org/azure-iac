# envs/dev/10-container-app-environment/main.tf
# -----------------------------------------------------------------------------
# Calls the container-app-environment child module. This root reads three
# upstream states:
#   - 01-resource-groups → app RG name (where the environment lives)
#   - 02-networking      → snet-<env>-app ID (compute-plane VNet
#                          integration; subnet is delegated to
#                          `Microsoft.App/environments` by module 02)
#   - 03-log-analytics   → LAW resource ID (container stdout/stderr sink)
#
# No other providers or data sources needed — CAE is a single azurerm
# resource wired to already-provisioned upstream outputs.
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map. Downstream
# Container Apps (module 11) consume the outputs re-exported here.
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
# Remote state — module 02 (networking)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "networking" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "networking/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Remote state — module 03 (log-analytics)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Container App Environment module call
# -----------------------------------------------------------------------------
module "container_app_environment" {
  source = "../../../modules/container-app-environment"

  env                        = var.env
  location                   = var.location
  resource_group_name        = data.terraform_remote_state.resource_groups.outputs.rg_app_name
  log_analytics_workspace_id = data.terraform_remote_state.log_analytics.outputs.law_id
  infrastructure_subnet_id   = data.terraform_remote_state.networking.outputs.subnet_app_id
  tags                       = local.tags
}
