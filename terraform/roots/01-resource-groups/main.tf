# roots/01-resource-groups/main.tf
# -----------------------------------------------------------------------------
# Calls the resource-groups child module and grants the Terraform SP
# blob-data access on the ai RG. Every downstream module reads its outputs
# via `data.terraform_remote_state`.
#
# See the module README for the 6 RGs and their lifecycle rationale, and
# docs/MODULES_DEPENDENCY.md for which modules consume which outputs.
# -----------------------------------------------------------------------------

module "resource_groups" {
  source = "../../modules/resource-groups"

  workload = var.workload
  env      = var.env
  location = var.location
  tags     = local.tags
}

# The Terraform SP needs blob-data access to create storage accounts with
# shared keys disabled. Granted here, once, because roots 17 and 18 both
# create storage in the ai RG and a duplicate assignment fails with 409.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "tf_sp_ai_blob_contributor" {
  scope                = module.resource_groups.rg_ai_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

# RBAC is eventually consistent; without this the storage poll can 403.
resource "time_sleep" "wait_for_ai_rbac" {
  depends_on      = [azurerm_role_assignment.tf_sp_ai_blob_contributor]
  create_duration = "60s"
}
