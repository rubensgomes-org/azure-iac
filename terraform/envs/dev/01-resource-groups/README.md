# 01-resource-groups (envs/dev)

Root Terraform config that provisions the 5 lifecycle-aligned Resource
Groups for the `dev` environment. State lives at key
`resource-groups/terraform.tfstate` in the backend blob container.

Wraps [`../../../modules/resource-groups/`](../../../modules/resource-groups/README.md).

## Prerequisites

- Bootstrap backend applied — the RG, storage account and blob container
  named by `TF_VAR_backend_resource_group_name`, `TF_VAR_storage_account_id`
  and `TF_VAR_container_name` all exist. See
  [`TF_BOOTSTRAP_CREATE.md`](../../../bootstrap-backend/TF_BOOTSTRAP_CREATE.md).
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell. See
  [`../../../INITIAL_SETUP.md`](../../../INITIAL_SETUP.md) for the SP setup.
- `../env.tfvars` populated with `env` and `location` — the ones this module
  reads.
- Both `.tfvars` files are gitignored and are NOT in a fresh clone. Create them
  once — see [`INITIAL_SETUP.md`](../../../INITIAL_SETUP.md) § Terraform
  Variable Files. Tags are not among their values: they come from the committed
  [`../tags.json`](../tags.json), with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/envs/dev/01-resource-groups

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=resource-groups/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

After a successful apply:

```bash
az group list \
  --query "[?starts_with(name,'rg-dev-')].{Name:name, Location:location, State:properties.provisioningState}" \
  -o table
```

Expected: 5 rows (`rg-dev-platform`, `rg-dev-network`, `rg-dev-data`,
`rg-dev-app`, `rg-dev-observability`), all with `State = Succeeded`. Names carry
a `-<suffix>` only when `TF_VAR_rg_suffix` is set — see the notes below. The
backend RG (`TF_VAR_backend_resource_group_name`) also matches the `rg-` prefix
but is unrelated to this module.

Read the outputs Terraform will hand to downstream modules:

```bash
terraform output resource_groups
terraform output rg_platform_id
```

## Destroy

```bash
cd terraform/envs/dev/01-resource-groups

terraform destroy
```

**Blocked while children exist.** `terraform destroy` refuses if any
resource lives in these RGs — that means every downstream module
(`02-networking` through `12-monitoring`) must be destroyed FIRST, in
reverse order. [`docs/MODULES_DEPENDENCY.md`](../../../../docs/MODULES_DEPENDENCY.md) has the full
dependency tree; destroy is that order reversed.

No post-destroy purge needed (RGs have no soft-delete window).

## Reprovision

Same commands as **Provision** — `terraform init` is idempotent, and RG names
are reusable immediately after destroy.

## Notes

- No `terraform.tfvars` values needed, and no file needed either. Nothing is
  passed unconditionally any more: `terraform.tfvars` is auto-loaded when
  present, and every value can come from a `TF_VAR_*` environment variable
  instead. See
  [INITIAL_SETUP](../../../INITIAL_SETUP.md#terraform-environment).
- The child module's set of purposes (`platform`, `network`, `data`, `app`,
  `observability`) is fixed on purpose. Adding one is a breaking change that
  every downstream module has to acknowledge.
- **`rg_suffix` is empty by default**, so the five RGs are `rg-dev-platform`,
  `rg-dev-network`, and so on, with no suffix. An empty value means exactly
  that — no suffix — which is also what CI produces when the repository
  variable is undefined, so a workflow run and a local run agree.
- **Overriding it renames every RG, and it comes from the environment, not
  tfvars.** `export TF_VAR_rg_suffix=blue` before `make apply-resource-groups`
  gives `rg-dev-platform-blue` instead. It is deliberately kept out of
  `env.tfvars.example`, and must stay out of any `env.tfvars` or
  `terraform.tfvars` you create locally, because `-var-file` and an
  auto-loaded `terraform.tfvars` both outrank `TF_VAR_*` — a value in either
  file would make the environment variable a silent no-op. The other eleven
  modules need no change: they read RG names from this module's remote
  state.

  Two limits worth knowing before using it:

  1. `name` is ForceNew on `azurerm_resource_group`. Changing the suffix on a
     live estate plans a destroy+recreate of all five RGs, but everything
     inside them is owned by other state files that know nothing about it —
     that is a broken estate, not a rename. Set it at first provision, or
     after a full teardown.
  2. Suffixed RGs alone do not make the estate parallel-safe. Key Vault,
     Storage, Service Bus, Log Analytics and PostgreSQL already append a
     `random_id`, but `acr_name` (supplied as `TF_VAR_acr_name`) is a fixed
     literal and will collide with the first estate's registry.

  `make purge-orphans` and the orphan sweep inside `make destroy` read the
  same `TF_VAR_rg_suffix`, so an override must be exported for teardown too —
  otherwise the sweep looks in `rg-dev-observability`, finds nothing, and
  module 01's destroy fails on `prevent_deletion_if_contains_resources`.
