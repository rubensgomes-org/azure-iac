# resource-groups (child module)

Creates the 5 lifecycle-aligned Azure Resource Groups that own every other
resource in this estate.

- `rg-<env>-platform` — Managed identities, Key Vault, ACR
- `rg-<env>-network` — VNet, subnets, NSGs, private DNS zones
- `rg-<env>-data` — PostgreSQL, Service Bus, Storage
- `rg-<env>-app` — Container App Environment, Container Apps
- `rg-<env>-observability` — Log Analytics, App Insights, Action Groups

The set of RGs is intentionally fixed. See
[`docs/PROVISIONING_PLAN.md`](../../../docs/PROVISIONING_PLAN.md) §3 for the
rationale (blast radius, dependency direction, lifecycle grouping).

## Inputs

| Name       | Type          | Required | Description                                       |
|------------|---------------|----------|---------------------------------------------------|
| `env`      | `string`      | yes      | Environment name (e.g. `dev`). Baked into names.  |
| `location` | `string`      | yes      | Azure region (e.g. `eastus`).                     |
| `tags`     | `map(string)` | no       | Common tags. `purpose` and `purpose_description` are added per-RG. |

## Outputs

Flat per-purpose:

- `rg_platform_{name,id,location}`
- `rg_network_{name,id,location}`
- `rg_data_{name,id,location}`
- `rg_app_{name,id,location}`
- `rg_observability_{name,id,location}`

Map form:

- `resource_groups` — `map(object({ name, id, location }))` keyed by purpose.

## Usage

Called from `terraform/envs/dev/01-resource-groups/main.tf`. This module
declares NO backend and NO provider — the calling root config supplies both.
