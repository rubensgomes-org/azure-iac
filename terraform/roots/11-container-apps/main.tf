# roots/11-container-apps/main.tf
# -----------------------------------------------------------------------------
# Calls the container-apps child module. This root reads five upstream
# states — every module that grants RBAC to the shared UAMI or provides a
# hostname the apps consume:
#
#   - 01-resource-groups        → app RG name (where the Container Apps live)
#   - 04-managed-identities     → shared UAMI id / name / client_id
#   - 05-key-vault              → vault URI (RBAC already granted in module 05)
#   - 06-acr                    → ACR login server (for `registry.server`)
#   - 10-container-app-environment → CAE id
#
# This root deliberately stays minimal: no database, blob storage, or
# Service Bus dependency until a workload actually needs one. Add the
# matching remote state block then and re-plan.
#
# See docs/MODULES_DEPENDENCY.md for the dependency map, and the module
# README for the passwordless wiring these remote-state reads make possible.
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
# Remote state — module 10 (container-app-environment)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Container Apps module call
# -----------------------------------------------------------------------------
module "container_apps" {
  source = "../../modules/container-apps"

  env                          = var.env
  resource_group_name          = data.terraform_remote_state.resource_groups.outputs.rg_app_name
  container_app_environment_id = data.terraform_remote_state.container_app_environment.outputs.cae_id
  apps                         = var.apps

  # Shared UAMI (module 04) — attached to every app for runtime identity
  # AND used as the ACR pull identity.
  uami_id        = data.terraform_remote_state.managed_identities.outputs.uami_app_id
  uami_client_id = data.terraform_remote_state.managed_identities.outputs.uami_app_client_id

  # ACR (module 06) — server for the `registry` block. Actual pull creds
  # come from the UAMI above (which holds `AcrPull` at ACR scope).
  acr_login_server = data.terraform_remote_state.acr.outputs.acr_login_server

  # Key Vault (module 05) — RBAC (`Key Vault Secrets User`) on the shared
  # UAMI was already granted in module 05; apps only need the vault URI.
  key_vault_uri = data.terraform_remote_state.key_vault.outputs.kv_uri

  # Per-app image + resource shape (all defaulted in the child module;
  # overrides arrive as TF_VAR_ exports -- this root is shared by every
  # environment and so holds no terraform.tfvars of its own).
  apps_image_map           = var.apps_image_map
  default_image            = var.default_image
  target_port              = var.target_port
  health_probe_paths       = var.health_probe_paths
  cpu                      = var.cpu
  memory                   = var.memory
  min_replicas             = var.min_replicas
  max_replicas             = var.max_replicas
  ingress_external_enabled = var.ingress_external_enabled

  tags = local.tags
}
