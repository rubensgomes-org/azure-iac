# roots/19-web-iq/main.tf
# -----------------------------------------------------------------------------
# Calls the web-iq child module. This root reads one upstream state:
#   - 01-resource-groups → ai RG ID (where the account lives)
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

module "web_iq" {
  source = "../../modules/web-iq"

  workload          = var.workload
  env               = var.env
  resource_group_id = data.terraform_remote_state.resource_groups.outputs.rg_ai_id
  tags              = local.tags
}
