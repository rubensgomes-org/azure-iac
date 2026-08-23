# envs/dev/01-resource-groups/backend.tf
# -----------------------------------------------------------------------------
# Empty azurerm backend block. Concrete values are supplied at `terraform init`
# time via two `-backend-config` flags:
#
#   terraform init \
#     -backend-config=../backend.hcl \
#     -backend-config="key=resource-groups/terraform.tfstate"
#
# The shared `../backend.hcl` provides `resource_group_name`,
# `storage_account_name`, `container_name`, and `use_azuread_auth`. The
# per-module `key` puts this module's state at
# `resource-groups/terraform.tfstate` inside the tfstate container.
#
# Backend blocks cannot interpolate variables — that's why this file is
# empty and the values live in backend.hcl instead.
# -----------------------------------------------------------------------------

terraform {
  backend "azurerm" {}
}
