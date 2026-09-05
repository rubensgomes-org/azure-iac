# envs/dev/11-container-apps/main.tf
# -----------------------------------------------------------------------------
# Calls the container-apps child module. This root reads seven upstream
# states — every module that grants RBAC to the shared UAMI or provides a
# hostname the apps consume:
#
#   - 01-resource-groups        → app RG name (where the Container Apps live)
#   - 04-managed-identities     → shared UAMI id / name / client_id
#   - 06-acr                    → ACR login server (for `registry.server`)
#   - 07-storage                → SA name + per-app blob container names
#   - 08-service-bus            → namespace FQDN
#   - 09-postgresql             → PG FQDN + per-app database names
#   - 10-container-app-environment → CAE id
#
# Module 05 (Key Vault) reads like a dependency but is NOT read
# here: apps consume shared secrets at runtime via `DefaultAzureCredential`
# (RBAC on the vault was already granted in module 05), not via Terraform-
# injected env vars. If a future app needs a KV URI baked into env, add
# module 05's remote state then and re-plan.
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
  source = "../../../modules/container-apps"

  env                          = var.env
  resource_group_name          = data.terraform_remote_state.resource_groups.outputs.rg_app_name
  container_app_environment_id = data.terraform_remote_state.container_app_environment.outputs.cae_id
  apps                         = var.apps

  # Shared UAMI (module 04) — attached to every app for runtime identity
  # AND used as the ACR pull identity. `uami_name` is the login PG expects
  # (registered as an AAD principal in module 09's data-plane bootstrap).
  uami_id        = data.terraform_remote_state.managed_identities.outputs.uami_app_id
  uami_name      = data.terraform_remote_state.managed_identities.outputs.uami_app_name
  uami_client_id = data.terraform_remote_state.managed_identities.outputs.uami_app_client_id

  # ACR (module 06) — server for the `registry` block. Actual pull creds
  # come from the UAMI above (which holds `AcrPull` at ACR scope).
  acr_login_server = data.terraform_remote_state.acr.outputs.acr_login_server

  # PG (module 09) — one server, one DB per app. Password auth is disabled
  # on the server; apps get AAD tokens via the SDK using the shared UAMI.
  postgres_host      = data.terraform_remote_state.postgresql.outputs.pg_fqdn
  postgres_databases = data.terraform_remote_state.postgresql.outputs.pg_databases

  # Storage (module 07) — one account, one blob container per app. Shared-
  # key auth is disabled; apps use `DefaultAzureCredential` for blob ops.
  storage_account_name    = data.terraform_remote_state.storage.outputs.sa_name
  storage_container_names = data.terraform_remote_state.storage.outputs.container_names

  # Service Bus (module 08) — one namespace, apps auth via AAD. Queue
  # names are NOT injected here today: module 08 defaults `queues = []`,
  # so `sb_queue_names` is empty. Add a `servicebus_queue_names` variable
  # to the child module when workloads actually need queues.
  servicebus_namespace_fqdn = data.terraform_remote_state.service_bus.outputs.sb_namespace_fqdn

  # Per-app image + resource shape (all defaulted in the child module;
  # overrides live in this root's terraform.tfvars).
  apps_image_map           = var.apps_image_map
  default_image            = var.default_image
  target_port              = var.target_port
  cpu                      = var.cpu
  memory                   = var.memory
  min_replicas             = var.min_replicas
  max_replicas             = var.max_replicas
  ingress_external_enabled = var.ingress_external_enabled

  tags = local.tags
}
