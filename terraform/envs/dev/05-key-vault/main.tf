# envs/dev/05-key-vault/main.tf
# -----------------------------------------------------------------------------
# Calls the key-vault child module. This root reads two upstream states:
#   - 01-resource-groups → platform RG name (where KV lives)
#   - 04-managed-identities → shared UAMI principal_id (target of the RBAC grant)
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map.
# Apps read secrets via the shared UAMI.
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
# Remote state — module 04 (managed-identities)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Key Vault module call
# -----------------------------------------------------------------------------
module "key_vault" {
  source = "../../../modules/key-vault"

  env                 = var.env
  prefix              = var.prefix
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_platform_name
  uami_principal_id   = data.terraform_remote_state.managed_identities.outputs.uami_app_principal_id
  tags                = local.tags
}
