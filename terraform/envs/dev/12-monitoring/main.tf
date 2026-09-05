# envs/dev/12-monitoring/main.tf
# -----------------------------------------------------------------------------
# Calls the monitoring child module. This root reads seven upstream states —
# every module that owns a resource this module attaches a diagnostic
# setting to, plus the RG and LAW references:
#
#   - 01-resource-groups → observability RG name (App Insights + action group)
#   - 03-log-analytics   → LAW id (backs App Insights AND is the diag sink)
#   - 05-key-vault       → KV id (diag setting target)
#   - 06-acr             → ACR id (diag setting target)
#   - 07-storage         → SA id (diag setting attaches at blob subresource)
#   - 08-service-bus     → SB namespace id (diag setting target)
#   - 09-postgresql      → PG server id (diag setting target)
#
# Modules 02 (network), 04 (UAMI), 10 (CAE), and 11 (Container Apps) are
# NOT read: 02/04 have no diagnostic categories worth capturing; 10 wires
# LAW directly on the environment (container stdout/stderr streams
# automatically); 11's apps stream through 10.
#
# See docs/MODULES_DEPENDENCY.md for the dependency map, and the module
# README for the observability posture.
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
# Remote state — module 03 (log-analytics)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "log_analytics" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "log-analytics/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Remote state — module 05 (key-vault)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "key_vault" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "key-vault/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Remote state — module 06 (acr)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "acr" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "acr/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Remote state — module 07 (storage)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "storage" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "storage/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Remote state — module 08 (service-bus)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "service_bus" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "service-bus/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Remote state — module 09 (postgresql)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "postgresql" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.backend_resource_group_name
    storage_account_name = var.storage_account_id
    container_name       = var.container_name
    key                  = "postgresql/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Monitoring module call
# -----------------------------------------------------------------------------
module "monitoring" {
  source = "../../../modules/monitoring"

  env                        = var.env
  location                   = var.location
  resource_group_name        = data.terraform_remote_state.resource_groups.outputs.rg_observability_name
  log_analytics_workspace_id = data.terraform_remote_state.log_analytics.outputs.law_id

  # Email receiver for the `owner` alert channel. Sourced from this
  # root's terraform.tfvars — see variables.tf on why it doesn't live in
  # ../env.tfvars.
  action_group_email = var.action_group_email

  # Diagnostic-setting targets — one per upstream resource that emits
  # logs worth keeping. Storage sends its id whole; the child module
  # composes `<sa_id>/blobServices/default` internally.
  key_vault_id             = data.terraform_remote_state.key_vault.outputs.kv_id
  acr_id                   = data.terraform_remote_state.acr.outputs.acr_id
  storage_account_id       = data.terraform_remote_state.storage.outputs.sa_id
  service_bus_namespace_id = data.terraform_remote_state.service_bus.outputs.sb_namespace_id
  postgresql_server_id     = data.terraform_remote_state.postgresql.outputs.pg_server_id

  tags = local.tags
}
