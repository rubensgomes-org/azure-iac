# resource-groups (child module)

Creates the 5 lifecycle-aligned Azure Resource Groups that own every other
resource in this estate.

- `rg-<workload>platform-<env>` — Managed identities, Key Vault, ACR
- `rg-<workload>network-<env>` — VNet, subnets, NSGs, private DNS zones
- `rg-<workload>data-<env>` — PostgreSQL, Service Bus, Storage
- `rg-<workload>app-<env>` — Container App Environment, Container Apps
- `rg-<workload>observability-<env>` — Log Analytics, App Insights, Action Groups

The set of RGs is intentionally fixed: one per lifecycle, so that a blast
radius stops at an RG boundary and the dependency direction between modules
stays one-way.

## Inputs

| Name       | Type          | Required | Description                                       |
|------------|---------------|----------|---------------------------------------------------|
| `workload` | `string`      | no       | CAF workload token. Default `rgomes`. 2-16 lowercase alnum. |
| `env`      | `string`      | yes      | Environment name (e.g. `lab`). Trailing token of every name. |
| `location` | `string`      | yes      | Azure region (e.g. `eastus`).                     |
| `tags`     | `map(string)` | no       | Common tags. `purpose` and `purpose_description` are added per-RG. |

Names follow the CAF form `rg-<workload><purpose>-<env>`. The purpose is folded
onto the workload token rather than given a dash of its own, so the name stays
at three tokens — see [NAMING.md](../../../docs/NAMING.md).

`workload` is safe to set at first provision or after a full teardown only:
`name` is ForceNew on `azurerm_resource_group`, and the resources inside those
RGs are owned by eleven other state files that would not follow a rename.

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

Called from `terraform/roots/01-resource-groups/main.tf`. This module
declares NO backend and NO provider — the calling root config supplies both.
