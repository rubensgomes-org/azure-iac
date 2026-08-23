# envs/dev/04-managed-identities/main.tf
# -----------------------------------------------------------------------------
# Calls the managed-identities child module. This root has no other
# resources — every downstream module reads the UAMI's outputs via
# `data.terraform_remote_state`.
#
# Reads module 01's state to get the platform RG name. Coupling to module 01
# is by remote-state key (`resource-groups/terraform.tfstate`), NOT by
# hard-coding `rg-<env>-platform`.
#
# See docs/PROVISIONING_PLAN.md §4 and §12 for the full dependency and
# passwordless-auth wiring.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Remote state — module 01 (resource-groups)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "resource_groups" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstaterubens01"
    container_name       = "tfstate"
    key                  = "resource-groups/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Managed Identities module call
# -----------------------------------------------------------------------------
module "managed_identities" {
  source = "../../../modules/managed-identities"

  env                 = var.env
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_platform_name
  tags                = merge(var.tags, { release = local.release })
}
