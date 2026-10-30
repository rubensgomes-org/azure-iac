# roots/16-foundry-project/main.tf
# -----------------------------------------------------------------------------
# Calls the foundry-project child module. One state per project, under the
# Foundry resource that module 15 created in the same region.
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map.
# -----------------------------------------------------------------------------

locals {
  location = coalesce(var.foundry_location, var.location)
}

data "terraform_remote_state" "foundry" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "foundry-resource/${local.location}/terraform.tfstate"
    use_azuread_auth     = false
  }
}

module "foundry_project" {
  source = "../../modules/foundry-project"

  workload    = var.workload
  env         = var.env
  location    = local.location
  name_suffix = var.foundry_project_suffix
  # Null when module 15 has no state in this region; the module rejects it.
  foundry_id = try(data.terraform_remote_state.foundry.outputs.foundry_id, null)
  tags       = local.tags
}
