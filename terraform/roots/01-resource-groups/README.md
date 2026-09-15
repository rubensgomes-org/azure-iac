# 01-resource-groups (terraform/roots)

Root Terraform config that provisions the 5 lifecycle-aligned Resource
Groups for the target environment. State lives at key
`resource-groups/terraform.tfstate` in the backend blob container.

Wraps [`../../modules/resource-groups/`](../../modules/resource-groups/README.md).

## Prerequisites

- Bootstrap backend applied — the RG, storage account and blob container
  named by `TF_VAR_backend_resource_group_name`, `TF_VAR_storage_account_id`
  and `TF_VAR_container_name` all exist. See
  [`TF_BOOTSTRAP_CREATE.md`](../../../docs/TF_BOOTSTRAP_CREATE.md).
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell. See
  [`INITIAL_SETUP.md`](../../../docs/INITIAL_SETUP.md) for the SP setup.
- `../../envs/<env>/env.tfvars` populated with `env` and `location` — the ones this module
  reads.
- `env.tfvars` is gitignored and is NOT in a fresh clone. Every value in it can
  come from a `TF_VAR_*` export instead, which is how CI runs and the simpler
  local setup — see
  [`INITIAL_SETUP.md`](../../../docs/INITIAL_SETUP.md) § Terraform Variable
  Files. Tags are not among its values: they come from the committed
  `envs/<env>/tags.json`, with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/roots/01-resource-groups

terraform init \
  -backend-config=../../envs/<env>/backend.hcl \
  -backend-config="key=resource-groups/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

After a successful apply:

```bash
az group list \
  --query "[?starts_with(name,'rg-${TF_VAR_workload:-rgomes}') && ends_with(name,'-${TF_VAR_env:-lab}')].{Name:name, Location:location, State:properties.provisioningState}" \
  -o table
```

Expected: 5 rows (`rg-rgomesplatform-lab`, `rg-rgomesnetwork-lab`,
`rg-rgomesdata-lab`, `rg-rgomesapp-lab`, `rg-rgomesobservability-lab`), all with
`State = Succeeded`. The query anchors both ends because the workload leads and
the environment trails — see the notes below. The backend RG
(`TF_VAR_backend_resource_group_name`) also starts with `rg-` but is unrelated
to this module, and the anchored query excludes it.

Read the outputs Terraform will hand to downstream modules:

```bash
terraform output resource_groups
terraform output rg_platform_id
```

## Destroy

```bash
cd terraform/roots/01-resource-groups

terraform destroy
```

**Blocked while children exist.** `terraform destroy` refuses if any
resource lives in these RGs — that means every downstream module
(`02-networking` through `12-monitoring`) must be destroyed FIRST, in
reverse order. [`docs/MODULES_DEPENDENCY.md`](../../../docs/MODULES_DEPENDENCY.md) has the full
dependency tree; destroy is that order reversed.

No post-destroy purge needed (RGs have no soft-delete window).

## Reprovision

Same commands as **Provision** — `terraform init` is idempotent, and RG names
are reusable immediately after destroy.

## Notes

- No `terraform.tfvars` values needed — and do not create the file. This root
  is shared by every environment, and Terraform auto-loads `terraform.tfvars`
  from the directory it runs in, so a file here would apply to `dev`, `lab` and
  anything after them alike, outranking the `TF_VAR_*` that was supposed to
  carry the difference. `make check-tfvars` refuses one. Every value comes from
  a `TF_VAR_*` environment variable; see
  [INITIAL_SETUP](../../../docs/INITIAL_SETUP.md#terraform-environment).
- The child module's set of purposes (`platform`, `network`, `data`, `app`,
  `observability`) is fixed on purpose. Adding one is a breaking change that
  every downstream module has to acknowledge.
- **`workload` defaults to `rgomes`**, so the five RGs are
  `rg-rgomesplatform-lab`, `rg-rgomesnetwork-lab`, and so on. Unlike the
  `rg_suffix` it replaced, `workload` lives in `env.tfvars` and is declared by
  all twelve roots — every resource name is composed from it rather than
  inherited through this module's remote state.
- **Changing it renames the whole estate.** `name` is ForceNew on
  `azurerm_resource_group`. Changing `workload` on a live estate plans a
  destroy+recreate of all five RGs, but everything inside them is owned by
  other state files that know nothing about it — that is a broken estate, not
  a rename. Set it at first provision, or after a full teardown.

  A parallel estate needs more than a different `workload`: `acr_name`
  (supplied as `TF_VAR_acr_name`) is a fixed literal and will collide with the
  first estate's registry, and since the CAF rename no resource carries a
  random suffix to fall back on.

  `make purge-orphans` and the orphan sweep inside `make destroy` read
  `TF_VAR_workload` and fall back to the same `rgomes`, so an override must be
  exported for teardown too — otherwise the sweep looks in
  `rg-rgomesobservability-lab`, finds nothing, and module 01's destroy fails
  on `prevent_deletion_if_contains_resources`.
