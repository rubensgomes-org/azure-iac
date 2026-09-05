# modules/container-app-environment

Child Terraform module that provisions one Azure Container Apps
Environment (ACAE / CAE) per environment. Consumed by module 11
(`container-apps`) — every `azurerm_container_app` attaches to this
environment via `container_app_environment_id = cae_id`.

Called by `terraform/envs/dev/10-container-app-environment/`. State is
owned by the caller — this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `azurerm_container_app_environment` | `cae-<env>` | Consumption-only, VNet-integrated on `snet-<env>-app`, external ingress, no zone redundancy. |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `env` | `string` | yes | Baked into the environment name. `^[a-z][a-z0-9]{1,9}$`. |
| `location` | `string` | yes | Azure region. Must match the RG and the subnet's VNet. |
| `resource_group_name` | `string` | yes | Caller passes `rg-<env>-app` (module 01 remote state). |
| `log_analytics_workspace_id` | `string` | yes | ARM resource ID of the LAW. Caller passes `law_id` (module 03 remote state). |
| `infrastructure_subnet_id` | `string` | yes | ARM resource ID of `snet-<env>-app`. Caller passes `subnet_app_id` (module 02 remote state). |
| `tags` | `map(string)` | no | Merged with `component = "container-app-environment"`. |

## Outputs

- `cae_id` — full Azure Resource ID; consumed by module 11.
- `cae_name`
- `cae_default_domain` — DNS suffix Azure assigns to apps in this env.
- `cae_static_ip_address` — public static IP for external ingress.
- `cae_location`

## Design decisions

- **Consumption-only workload profile.** No `workload_profile` block is
  declared; azurerm 5.x treats that as Consumption-only, which bills
  per-request and needs no reserved capacity. Add explicit blocks (e.g.
  `D4`, `E4`) later if a workload needs dedicated compute.
- **External ingress** (`internal_load_balancer_enabled = false`).
  Public static IP so the browser can hit apps directly. Flip to
  `true` for private-only ingress (requires VPN / bastion / peered
  VNet).
- **No zone redundancy** (`zone_redundancy_enabled = false`). Enabling
  it demands a subnet that spans all three AZs in the region; module
  02 provisions a single-AZ /23. Enabling here without fixing the
  subnet fails at apply time.
- **Fixed name `cae-<env>`.** Unlike LAW / KV / SA / PG, Container App
  Environments have no soft-delete window — `terraform destroy` frees
  the name immediately. No random suffix needed.
- **Log Analytics via `log_analytics_workspace_id`.** azurerm accepts
  the workspace's ARM resource ID directly; the legacy `customer_id` +
  `primary_shared_key` pair is not required. The module also sets
  `logs_destination = "log-analytics"`, which azurerm 5.0 stopped
  inferring from the workspace ID.

## Destroy notes

Container Apps (module 11) attach to this environment. Azure refuses to
delete a CAE while any Container App inside it still exists — always
`terraform destroy` module 11 first, then this one. If a stuck app
survives (e.g. a manually-created one outside Terraform), delete it via
`az containerapp delete -g rg-<env>-app -n <app-name> --yes` before
retrying destroy on this module.
