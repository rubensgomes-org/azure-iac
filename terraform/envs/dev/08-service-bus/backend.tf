# envs/dev/08-service-bus/backend.tf
# -----------------------------------------------------------------------------
# Empty azurerm backend block. Concrete values are supplied at `terraform init`
# time via two `-backend-config` flags:
#
#   terraform init \
#     -backend-config=../backend.hcl \
#     -backend-config="key=service-bus/terraform.tfstate"
#
# The shared `../backend.hcl` provides `resource_group_name`,
# `storage_account_name`, `container_name`, and `use_azuread_auth`. The
# per-module `key` puts this module's state at `service-bus/terraform.tfstate`
# inside the tfstate container.
#
# Backend blocks cannot interpolate variables — that's why this file is
# empty and the values live in backend.hcl instead.
# -----------------------------------------------------------------------------

terraform {
  backend "azurerm" {}
}
