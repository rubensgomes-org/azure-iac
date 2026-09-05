# envs/dev/07-storage/main.tf
# -----------------------------------------------------------------------------
# Calls the storage child module. This root reads two upstream states:
#   - 01-resource-groups → data RG name (where the storage account lives)
#   - 04-managed-identities → shared UAMI principal_id (target of the RBAC grant)
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map.
# Apps read and write blobs via the shared UAMI.
#
# This root also grants the TERRAFORM SP (not just the UAMI) blob-data
# access on the data RG. That grant is a bootstrap concern of the storage
# module specifically — see the `tf_sp_blob_contributor` block below.
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
# Terraform SP → Storage Blob Data Contributor (data RG scope)
# -----------------------------------------------------------------------------
# Why this exists (only in this module):
#
#   The storage account is provisioned with `shared_access_key_enabled =
#   false` and the azurerm provider is set to `storage_use_azuread = true`
#   (see providers.tf). After creating the SA, azurerm polls the blob
#   service data plane to confirm the account is ready — using the SP's
#   AAD token. Without a data-plane role, that call 403s and the whole
#   `azurerm_storage_account` create fails.
#
# Scope: data RG (`rg-<env>-data`). Broader than the SA (which doesn't
# exist yet at role-assignment time — can't scope role to a
# not-yet-created resource) but narrower than subscription. Every future
# SA in this RG inherits the grant.
#
# `principal_type = "ServicePrincipal"` avoids a slow/failing Entra
# lookup during plan.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "tf_sp_blob_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${data.terraform_remote_state.resource_groups.outputs.rg_data_name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

# RBAC propagation wait. Azure IAM is eventually consistent — a fresh
# role assignment can take 30-60s before the data plane sees it. Without
# this delay, the SA's post-create data-plane poll races the role and
# 403s intermittently.
#
# `create_duration` runs once per lifecycle of the sleep resource; the
# resource itself is idempotent on subsequent applies (won't re-wait).
resource "time_sleep" "wait_for_rbac" {
  depends_on      = [azurerm_role_assignment.tf_sp_blob_contributor]
  create_duration = "60s"
}

# -----------------------------------------------------------------------------
# Storage module call
# -----------------------------------------------------------------------------
# `depends_on` forces the module (and therefore the SA inside it) to wait
# until the RBAC-propagation sleep completes. Without this, the module's
# SA create races the role assignment.
module "storage" {
  source = "../../../modules/storage"

  env                 = var.env
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_data_name
  uami_principal_id   = data.terraform_remote_state.managed_identities.outputs.uami_app_principal_id
  apps                = var.apps
  tags                = local.tags

  depends_on = [time_sleep.wait_for_rbac]
}
