# modules/key-vault/main.tf
# -----------------------------------------------------------------------------
# Provisions one Key Vault per env plus the RBAC grant that lets the shared
# UAMI read secrets. Consumers:
#   - Container Apps (module 11) — read shared secrets via DefaultAzureCredential.
#   - Future modules that store certificates or connection strings the
#     estate doesn't have yet (third-party API keys, TLS certs, etc.).
#
# What LIVES here vs. elsewhere:
#   ✓ Vault + auth mode + network posture + one RBAC grant.
#   ✗ Individual secrets — those belong in the module that owns the secret's
#     lifecycle (or are omitted entirely because the passwordless model
#     doesn't need them).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Tenant lookup
# -----------------------------------------------------------------------------
# Key Vault needs the tenant_id at create time. Reading it from the current
# provider config avoids passing tenant as yet another variable — the SP the
# Terraform run authenticates with is always in the target tenant.
data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# Dev-friendly safety toggles (locals)
# -----------------------------------------------------------------------------
#
#   - `standard` SKU: cheapest; premium is only needed for HSM-backed keys.
#   - `rbac_authorization_enabled = true`: Azure RBAC controls data-plane
#     access (matches the passwordless model). Access policies are the
#     legacy alternative — do NOT mix them with RBAC on the same vault.
#   - `purge_protection_enabled = false`: lets us wipe and reuse the name
#     on the same day. Prod should flip this to `true`.
#   - `soft_delete_retention_days = 7`: minimum allowed. Cuts the purge
#     window from the default 90 days.
#   - `public_network_access_enabled = true` + `default_action = "Allow"`:
#     public reachability from the Terraform SP and any dev laptop. RBAC
#     is the auth gate; tightening the network is a follow-up when we add
#     a private endpoint against `privatelink.vaultcore.azure.net` (zone
#     already provisioned in module 02).
locals {
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

# -----------------------------------------------------------------------------
# Key Vault
# -----------------------------------------------------------------------------
# Name pattern: the plain CAF form kv-<workload>-<env> (e.g. "kv-rgomes-lab").
# Max 24 chars, alphanumeric + hyphens — the `workload` (≤16) and `env` (≤10)
# validations plus the 4 literal chars can exceed that, so the precondition
# below asserts the composed length rather than trusting the two separately.
#
# TWO THINGS THIS DELIBERATELY GIVES UP by dropping the former random suffix:
#
#   1. Global uniqueness. KV names are unique across every Azure tenant, so
#      `kv-<workload>-<env>` can collide with a stranger's vault. That is the
#      price of a name an operator can derive from env.tfvars; pick a workload
#      token distinctive enough to survive it.
#   2. Soft-delete-safe re-provision. A deleted vault's name is held in the
#      recycle bin for `soft_delete_retention_days` (7 here) and a rebuild
#      inside that window fails. Recover with:
#
#        az keyvault purge --name kv-<workload>-<env>
#
# See docs/NAMING.md and docs/TEARDOWN.md.
resource "azurerm_key_vault" "this" {
  name                = "kv-${var.workload}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = local.sku_name

  rbac_authorization_enabled = local.rbac_authorization_enabled
  purge_protection_enabled   = local.purge_protection_enabled
  soft_delete_retention_days = local.soft_delete_retention_days

  public_network_access_enabled = true

  # Even with public network enabled, network_acls must be present in
  # azurerm 5.x for a KV that faces the public Internet. `Allow` default
  # matches "public network enabled"; if we later add a private endpoint,
  # flip default_action to "Deny" and add explicit IP allow-lists or
  # virtual_network_subnet_ids as needed.
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = merge(
    var.tags,
    { component = "key-vault" },
  )

  # `workload` (≤16) and `env` (≤10) validate independently, so a legal pair
  # can still compose a 30-char name. Azure would reject it at apply time with
  # an opaque API error; fail at plan time with a message that names the
  # offending value instead.
  lifecycle {
    precondition {
      condition     = length("kv-${var.workload}-${var.env}") <= 24
      error_message = "Key Vault name kv-${var.workload}-${var.env} exceeds 24 chars. Shorten workload or env."
    }
  }
}

# -----------------------------------------------------------------------------
# RBAC — Key Vault Secrets User for the shared UAMI
# -----------------------------------------------------------------------------
# The shared UAMI (from module 04) is the auth principal for every
# microservice. `Key Vault Secrets User` is the minimum-privilege role that
# lets a caller read secret values — enough for DefaultAzureCredential to
# fetch third-party API keys or connection strings. It does NOT let the
# caller write secrets, which is intentional: writes go through Terraform.
resource "azurerm_role_assignment" "uami_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.uami_principal_id

  # `principal_type = "ServicePrincipal"` avoids a slow Entra lookup on
  # every plan — UAMIs surface as service principals. Skipping this makes
  # Terraform infer the type, which occasionally fails on brand-new
  # identities (Entra hasn't propagated yet).
  principal_type = "ServicePrincipal"
}
