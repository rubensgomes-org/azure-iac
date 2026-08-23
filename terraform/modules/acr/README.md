# modules/acr

Child Terraform module that provisions one Azure Container Registry per
environment plus the single RBAC role assignment (`AcrPull`) that lets the
shared UAMI pull images.

Called by `terraform/envs/dev/06-acr/`. State is owned by the caller —
this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `random_id` | `suffix` | 4-hex-char suffix; keyed on `env`. |
| `azurerm_container_registry` | `acr<env><random>` | SKU `Basic`, `admin_enabled = false`, public network enabled. |
| `azurerm_role_assignment` | `AcrPull` for UAMI | Role `AcrPull` at registry scope. |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `env` | `string` | yes | Baked into name and random keeper. `^[a-z][a-z0-9]{1,9}$`. |
| `location` | `string` | yes | Azure region. Must match the RG's location. |
| `resource_group_name` | `string` | yes | Caller passes `rg-<env>-platform` (from module 01). |
| `uami_principal_id` | `string` | yes | `principal_id` of the shared UAMI (from module 04). |
| `tags` | `map(string)` | no | Merged with `component = "acr"`. |

## Outputs

- `acr_id` — full Azure Resource ID
- `acr_name` — registry name
- `acr_login_server` — `<name>.azurecr.io` (passed to Container Apps)
- `acr_location`
- `acr_role_assignment_id`

## Design decisions

- **SKU `Basic`.** Cheapest tier that supports managed-identity pull, which
  is the only capability the playground needs. Standard bumps storage
  quota (100 GiB vs. 10) and throughput; Premium unlocks private
  endpoints, geo-replication, content trust, and token/scope maps.
  Upgrade path: change `local.sku` to `Premium` in `main.tf` and (if
  wanted) add an `azurerm_private_endpoint` on `snet-<env>-pe` wired to
  `privatelink.azurecr.io` (zone from module 02).
- **`admin_enabled = false`.** No username/password. Enabling this
  contradicts the passwordless model.
- **Public network enabled.** Matches the playground posture. Basic can't
  gate access to a PE anyway.
- **Random suffix in the name.** ACR names are globally unique across
  every Azure tenant. Random keeps the module collision-safe.
- **AcrPull only, no AcrPush.** Apps pull at runtime; push happens from
  CI or `docker push` with an ad-hoc token. Adding push permission to
  the shared UAMI would let a compromised app overwrite images.

## Skipped dependencies (vs. the plan)

`docs/PROVISIONING_PLAN.md` §4 lists modules 02 (network) and 05
(Key Vault) as ACR dependencies. Neither has a structural dep in the
current design:

- **02 network:** Basic SKU can't host a private endpoint, so nothing to
  wire. If we upgrade to Premium and add a PE, wire remote state to
  module 02 here.
- **05 Key Vault:** There's no ACR admin credential to store — the
  passwordless model means the registry has no username/password. If we
  ever add a customer-managed key for encryption-at-rest, wire remote
  state to module 05 here.

## Downstream consumers

- **Container Apps (module 11):** each `azurerm_container_app` gets a
  `registries { server = <acr_login_server>, identity = <shared-uami-id> }`
  block for passwordless image pull.
