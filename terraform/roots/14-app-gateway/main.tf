# roots/14-app-gateway/main.tf
# -----------------------------------------------------------------------------
# Calls the app-gateway child module. This root reads four upstream states:
#   - 01-resource-groups → network RG name (where the gateway lives)
#   - 02-networking → gateway subnet and NSG IDs
#   - 11-container-app-environment → environment static IP (backend)
#   - 12-container-apps → FQDN of `var.public_app` (backend host name);
#     plan fails if module 12 does not deploy that app
#
# See docs/MODULES_DEPENDENCY.md for the full dependency map.
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

data "terraform_remote_state" "networking" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "networking/terraform.tfstate"
    use_azuread_auth     = false
  }
}

data "terraform_remote_state" "container_app_environment" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "container-app-environment/terraform.tfstate"
    use_azuread_auth     = false
  }
}

data "terraform_remote_state" "container_apps" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "container-apps/terraform.tfstate"
    use_azuread_auth     = false
  }
}

module "app_gateway" {
  source = "../../modules/app-gateway"

  workload            = var.workload
  env                 = var.env
  location            = var.location
  resource_group_name = data.terraform_remote_state.resource_groups.outputs.rg_network_name
  subnet_id           = data.terraform_remote_state.networking.outputs.subnet_agw_id
  nsg_id              = data.terraform_remote_state.networking.outputs.nsg_agw_id
  dns_label           = coalesce(var.dns_label, "${var.public_app}-${var.env}")
  public_source_cidrs = var.public_source_cidrs
  backend_ip_address  = data.terraform_remote_state.container_app_environment.outputs.cae_static_ip_address
  backend_host_name   = data.terraform_remote_state.container_apps.outputs.app_fqdns[var.public_app]
  tags                = local.tags
}
