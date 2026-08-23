# modules/key-vault

Child Terraform module that provisions one Key Vault per environment plus
the single RBAC role assignment that lets the shared UAMI read secrets.

Called by `terraform/envs/dev/05-key-vault/`. State is owned by the caller —
this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `random_id` | `suffix` | 4-hex-char suffix; keyed on `env` + `prefix`. |
| `azurerm_key_vault` | `kv-<env>-<prefix>-<random>` | SKU `standard`, RBAC mode, public network enabled. |
| `azurerm_role_assignment` | Secrets User for UAMI | Role `Key Vault Secrets User` at vault scope. |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `env` | `string` | yes | Baked into name and random keeper. `^[a-z][a-z0-9]{1,9}$`. |
| `prefix` | `string` | yes | Owner/org token. `^[a-z][a-z0-9]{1,15}$`. Total name ≤ 24 chars. |
| `location` | `string` | yes | Azure region. Must match the RG's location. |
| `resource_group_name` | `string` | yes | Caller passes `rg-<env>-platform` (from module 01). |
| `uami_principal_id` | `string` | yes | `principal_id` of the shared UAMI (from module 04). |
| `tags` | `map(string)` | no | Merged with `component = "key-vault"`. |

## Outputs

- `kv_id` — full Azure Resource ID
- `kv_name` — vault name (capture BEFORE destroy for `az keyvault purge`)
- `kv_uri` — `https://<name>.vault.azure.net/`
- `kv_location`
- `kv_role_assignment_id`

## Design decisions

- **RBAC-mode auth (`enable_rbac_authorization = true`).** Matches the
  passwordless RBAC-everywhere model. Do NOT mix with access policies.
- **`standard` SKU.** Premium (HSM-backed keys) not needed for the
  playground.
- **Dev safety toggles: `purge_protection_enabled = false`,
  `soft_delete_retention_days = 7`.** See `docs/PROVISIONING_PLAN.md` §9.
  Prod should flip purge protection on.
- **Public network enabled, `default_action = "Allow"`, bypass Azure
  Services.** Simplest playground posture — RBAC is the auth gate.
  Adding a private endpoint later is a small change: create
  `azurerm_private_endpoint` on `snet-<env>-pe`, wire it to
  `privatelink.vaultcore.azure.net` (module 02), flip `default_action` to
  `Deny`.
- **Random suffix in the name.** KV names are globally unique. Random
  covers both collision avoidance and 7-day soft-delete recycle bin
  sidestepping.
- **One role assignment only (`Key Vault Secrets User`).** Enough for the
  passwordless model — apps READ shared secrets, writes go through
  Terraform. Additional roles (Certificates User, Crypto User) can be
  added if a specific workload needs them.

## Downstream consumers

- **Container Apps (module 11):** read secrets via `DefaultAzureCredential`
  + `SecretClient`, using the shared UAMI. Pass `kv_uri` as
  `KEY_VAULT_URI` env var.
