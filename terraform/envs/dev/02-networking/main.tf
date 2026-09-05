# envs/dev/02-networking/main.tf
# -----------------------------------------------------------------------------
# Calls the networking child module. This root has no other resources —
# every downstream module reads its outputs via `data.terraform_remote_state`.
#
# Reads module 01's state to get the network RG name. Coupling to module 01
# is by remote-state key (`resource-groups/terraform.tfstate`), NOT by
# hard-coding `rg-<env>-network`, so a rename in module 01 propagates
# automatically.
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Remote state — module 01 (resource-groups)
# -----------------------------------------------------------------------------
# Reads the RG names/IDs from module 01's state file, which lives at
# `resource-groups/terraform.tfstate` inside the shared state container.
# The three coordinates come from variables defaulted to the same values as
# ../backend.hcl, so CI can point this read at another backend via TF_VAR_*.
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
# Networking module call
# -----------------------------------------------------------------------------
module "networking" {
  source = "../../../modules/networking"

  env                 = var.env
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_network_name
  tags                = local.tags
}
