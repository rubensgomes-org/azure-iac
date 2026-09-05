# envs/dev/03-log-analytics/main.tf
# -----------------------------------------------------------------------------
# Calls the log-analytics child module. This root has no other resources —
# every downstream module reads its outputs via `data.terraform_remote_state`.
#
# Reads module 01's state to get the observability RG name. Coupling to
# module 01 is by remote-state key (`resource-groups/terraform.tfstate`),
# NOT by hard-coding `rg-<env>-observability`.
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map.
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
# Log Analytics module call
# -----------------------------------------------------------------------------
module "log_analytics" {
  source = "../../../modules/log-analytics"

  env                 = var.env
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_observability_name
  tags                = local.tags
}
