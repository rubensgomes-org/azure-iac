# envs/dev/01-resource-groups/main.tf
# -----------------------------------------------------------------------------
# Calls the resource-groups child module. This root has no other resources —
# every downstream module reads its outputs via `data.terraform_remote_state`.
#
# See docs/PROVISIONING_PLAN.md §3 for the 5 RGs and their lifecycle
# rationale, and §4 for which downstream modules consume which outputs.
# -----------------------------------------------------------------------------

module "resource_groups" {
  source = "../../../modules/resource-groups"

  env       = var.env
  location  = var.location
  rg_suffix = var.rg_suffix
  tags      = merge(var.tags, { release = local.release })
}
