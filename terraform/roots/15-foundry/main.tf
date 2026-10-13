# roots/15-foundry/main.tf
# -----------------------------------------------------------------------------
# Calls the foundry child module. This root reads one upstream state:
#   - 01-resource-groups → ai RG name (where the Foundry resource lives)
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
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

module "foundry" {
  source = "../../modules/foundry"

  workload            = var.workload
  env                 = var.env
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_ai_name
  # An unset Actions variable arrives as "", which means "no grant".
  foundry_user_object_id = var.foundry_user_object_id == "" ? null : var.foundry_user_object_id
  tags                   = local.tags
}
