# resource-groups (child module)

Creates the 5 lifecycle-aligned Azure Resource Groups that own every other
resource in this estate.

- `rg-<env>-platform` — Managed identities, Key Vault, ACR
- `rg-<env>-network` — VNet, subnets, NSGs, private DNS zones
- `rg-<env>-data` — PostgreSQL, Service Bus, Storage
- `rg-<env>-app` — Container App Environment, Container Apps
- `rg-<env>-observability` — Log Analytics, App Insights, Action Groups

The set of RGs is intentionally fixed: one per lifecycle, so that a blast
radius stops at an RG boundary and the dependency direction between modules
stays one-way.

## Inputs

| Name       | Type          | Required | Description                                       |
|------------|---------------|----------|---------------------------------------------------|
| `env`      | `string`      | yes      | Environment name (e.g. `dev`). Baked into names.  |
| `location` | `string`      | yes      | Azure region (e.g. `eastus`).                     |
| `rg_suffix`| `string`      | no       | Appends `-<suffix>` to every RG name. Default empty (= no suffix). |
| `tags`     | `map(string)` | no       | Common tags. `purpose` and `purpose_description` are added per-RG. |

`rg_suffix` is empty by default, so the five RGs are `rg-<env>-<purpose>` with
no suffix. An empty value means exactly that — no suffix — which is also what
CI produces when the `TF_VAR_rg_suffix` repository variable is undefined, so a
workflow run and a local run land on the same names.

`rg_suffix` is overridden through the `TF_VAR_rg_suffix` environment variable
rather than a tfvars file — `-var-file` outranks `TF_VAR_*`, so a value in
`env.tfvars` would silently win over the environment. It is safe
to set at first provision or after a full teardown only: `name` is ForceNew on
`azurerm_resource_group`, and the resources inside those RGs are owned by
eleven other state files that would not follow a rename.

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
