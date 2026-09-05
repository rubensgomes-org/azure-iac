# modules/acr

Child Terraform module that provisions one Azure Container Registry per
environment plus the single RBAC role assignment (`AcrPull`) that lets the
shared UAMI pull images.

Called by `terraform/envs/dev/06-acr/`. State is owned by the caller —
this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `azurerm_container_registry` | `var.acr_name` (dev: `rubensdevacr`) | SKU `Basic`, `admin_enabled = false`, public network enabled. |
| `azurerm_role_assignment` | `AcrPull` for UAMI | Role `AcrPull` at registry scope. |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `acr_name` | `string` | yes | Explicit registry name. `^[a-zA-Z0-9]{5,50}$`, globally unique across Azure. Dev: `rubensdevacr`. |
| `env` | `string` | yes | Not part of the registry name; kept for tag/convention parity. `^[a-z][a-z0-9]{1,9}$`. |
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
- **Explicit name, no random suffix.** ACR names are globally unique
  across every Azure tenant, but the registry name is a memorable literal
  passed in as `var.acr_name` (`rubensdevacr` in dev) rather than the
  `acr<env><random>` pattern the rest of the estate uses. A random suffix
  would change the image references in `apps_image_map` on every
  destroy+recreate. The trade-off is that a name collision fails the apply
  with an availability error instead of being routed around — Basic ACR
  has no soft-delete, so the name is free again the moment you destroy.
- **AcrPull only, no AcrPush.** Apps pull at runtime; push happens from
  CI or `docker push` with an ad-hoc token. Adding push permission to
  the shared UAMI would let a compromised app overwrite images.

## Not dependencies

Modules 02 (network) and 05 (Key Vault) read like ACR dependencies, but
neither has a structural dep in the current design:

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
