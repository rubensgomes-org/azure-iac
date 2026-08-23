# envs/dev/09-postgresql/main.tf
# -----------------------------------------------------------------------------
# Calls the postgresql child module. This root reads two upstream states:
#   - 01-resource-groups → data RG name (where the server lives)
#   - 04-managed-identities → shared UAMI name (registered as an AAD principal
#     inside PG by the child module's null_resource)
#
# And two fresh lookups on every plan:
#   - `azurerm_client_config.current` → tenant_id
#   - `http.myip` → the runner's public IPv4 (added as a single-IP firewall
#     rule so the psql call can reach the server)
#
# The Entra admin group's display name is passed EXPLICITLY as
# `var.pg_entra_admin_group_name` from env.tfvars rather than looked up
# via `data.azuread_group`. The lookup requires `Directory.Read.All` /
# `Group.Read.All` on the Terraform SP — a playground SP typically lacks
# both, and granting them needs tenant admin consent.
#
# See docs/PROVISIONING_PLAN.md §4 for the full dependency map and §12 for
# the passwordless-auth wiring (apps auth to PG via `DefaultAzureCredential`
# using the same shared UAMI). Master plan §12 item 5 documents the
# public-bootstrap posture used here — flip to VNet-only later.
#
# Modules 02 (network) and 05 (Key Vault) are listed as postgresql
# dependencies in §4 but are not consumed here:
#   - 02: `delegated_subnet_id = snet-pg` is unused during the public
#     bootstrap phase. Wire remote state to module 02 when we flip to
#     VNet-only.
#   - 05: no customer-managed key for encryption-at-rest, no SQL admin
#     password to stash (password auth is disabled).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Remote state — module 01 (resource-groups)
# -----------------------------------------------------------------------------
data "terraform_remote_state" "resource_groups" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstaterubens01"
    container_name       = "tfstate"
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
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstaterubens01"
    container_name       = "tfstate"
    key                  = "managed-identities/terraform.tfstate"
    use_azuread_auth     = false
  }
}

# -----------------------------------------------------------------------------
# Tenant lookup
# -----------------------------------------------------------------------------
# Server's `authentication.tenant_id` and the AAD administrator resource
# both need the current tenant. Reading it from the provider config
# avoids passing tenant as yet another variable.
data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# Runner public IP lookup
# -----------------------------------------------------------------------------
# The child module adds a single-IP firewall rule so the null_resource
# psql call can reach the server. api.ipify.org is a widely-used, no-auth
# IP echo service; if it ever goes down, swap to ifconfig.me or
# checkip.amazonaws.com — the response format is a bare IPv4 in all three.
#
# `trimspace` guards against trailing newline. The output is validated
# by the child module's `runner_public_ip` variable regex.
data "http" "myip" {
  url = "https://api.ipify.org"
}

# -----------------------------------------------------------------------------
# PostgreSQL module call
# -----------------------------------------------------------------------------
module "postgresql" {
  source = "../../../modules/postgresql"

  env                            = var.env
  location                       = var.location
  resource_group_name            = data.terraform_remote_state.resource_groups.outputs.rg_data_name
  tenant_id                      = data.azurerm_client_config.current.tenant_id
  pg_entra_admin_group_object_id = var.pg_entra_admin_group_object_id
  pg_entra_admin_group_name      = var.pg_entra_admin_group_name
  runner_public_ip               = trimspace(data.http.myip.response_body)
  apps                           = var.apps
  uami_name                      = data.terraform_remote_state.managed_identities.outputs.uami_app_name
  tags                           = merge(var.tags, { release = local.release })

  # Data-plane bootstrap OFF by default. This runner's network blocks
  # outbound TCP 5432 (both to Azure and everywhere), so an in-line
  # psql step cannot complete. Instead the same SQL is run ONCE from
  # Azure Cloud Shell (which egresses inside Azure and is covered by
  # the `allow-azure-services` firewall rule). See README →
  # "Data-plane bootstrap" for the exact commands. A follow-on refactor
  # will move this into a Container Apps Job triggered by GitHub
  # Actions — see docs/PROVISIONING_PLAN.md §12a — at which point this
  # variable and the null_resource go away.
  run_bootstrap = false
}
