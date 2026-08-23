# modules/networking

Child Terraform module that provisions the network plane for one environment:
one VNet, three subnets (with NSGs), and five private DNS zones linked to
the VNet.

Called by `terraform/envs/dev/02-networking/`. State is owned by the caller —
this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `azurerm_virtual_network` | `vnet-<env>` | `10.0.0.0/16` |
| `azurerm_subnet` | `snet-<env>-app` | `10.0.0.0/23`, delegated to `Microsoft.App/environments` |
| `azurerm_subnet` | `snet-<env>-pg` | `10.0.4.0/24`, delegated to `Microsoft.DBforPostgreSQL/flexibleServers` |
| `azurerm_subnet` | `snet-<env>-pe` | `10.0.5.0/24`, `private_endpoint_network_policies = Disabled` |
| `azurerm_network_security_group` | `nsg-<env>-{app,pg,pe}` | One per subnet, default rules only, associated |
| `azurerm_private_dns_zone` | 5 zones (see below) | One per downstream PE-integrated service |
| `azurerm_private_dns_zone_virtual_network_link` | `vnet-link-<env>-<key>` | One per zone; `registration_enabled = false` |

Private DNS zones:

| Key | Zone | For |
|-----|------|-----|
| `kv`   | `privatelink.vaultcore.azure.net`    | Key Vault |
| `blob` | `privatelink.blob.core.windows.net`  | Storage (Blob endpoint) |
| `acr`  | `privatelink.azurecr.io`             | Azure Container Registry |
| `sb`   | `privatelink.servicebus.windows.net` | Service Bus |
| `pg`   | `private.postgres.database.azure.com`| PostgreSQL Flexible Server (uses `private.*`, not `privatelink.*`) |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `env` | `string` | yes | Baked into every resource name. `^[a-z][a-z0-9]{1,9}$`. |
| `location` | `string` | yes | Azure region. Must match the RG's location. |
| `resource_group_name` | `string` | yes | RG that holds every resource. Caller passes `rg-<env>-network` (from module 01's remote state). |
| `tags` | `map(string)` | no | Applied to VNet, NSGs, DNS zones, VNet links. Subnets don't support tags in azurerm. |

## Outputs

- `vnet_id`, `vnet_name`, `vnet_address_space`
- `subnet_app_id`, `subnet_pg_id`, `subnet_pe_id`
- `nsg_app_id`, `nsg_pg_id`, `nsg_pe_id`
- `dns_zone_{kv,blob,acr,sb,pg}_id`
- `subnets` — map `key => {id, name, cidr}` for every subnet
- `private_dns_zones` — map `key => {name, id}` for every zone

## Design decisions

- **Fixed subnet set (`app`, `pg`, `pe`).** Every downstream module reads
  these by key. Adding a subnet here is a breaking change that must be
  coordinated across the estate — same reasoning as
  `modules/resource-groups`.
- **Address plan hard-coded in `main.tf`.** CIDRs live in a local, not as
  variables. Making them tunable adds no value in a single-env playground
  and risks drift between environments.
- **No custom NSG rules.** Azure's default rules cover the playground
  posture (VNet-internal allowed, inbound Internet denied). Add rules later
  when a specific service needs one.
- **`registration_enabled = false` on every VNet link.** Private-endpoint
  services register their own A records into these zones; the VNet should
  NOT auto-register VM hostnames alongside them.
- **PG DNS zone uses `private.*`, not `privatelink.*`.** PostgreSQL
  Flexible Server predates the standardised `privatelink.*` pattern. Do not
  change this name — the flex server binds records to this exact zone.
