# 01-resource-groups (envs/dev)

Root Terraform config that provisions the 5 lifecycle-aligned Resource Groups
for the `dev` environment. State lives in
`tfstate/resource-groups/terraform.tfstate` on the bootstrap storage account.

Wraps [`../../../modules/resource-groups/`](../../../modules/resource-groups/README.md).

## Prerequisites

- Bootstrap backend applied (RG `rg-tfstate`, storage `sttfstaterubens01`,
  container `tfstate` exist).
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell. See
  [`../../../INITIAL_SETUP.md`](../../../INITIAL_SETUP.md) for the SP setup.
- `../env.tfvars` populated (env, location, tags — the ones this module reads).

## Provision

```bash
cd terraform/envs/dev/01-resource-groups

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=resource-groups/terraform.tfstate"

terraform plan \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars \
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
`rg-dev-app`, `rg-dev-observability`), all with `State = Succeeded`, plus
the existing `rg-tfstate` unrelated to this module.

Read the outputs Terraform will hand to downstream modules:

```bash
terraform output resource_groups
terraform output rg_platform_id
```

## Destroy

```bash
cd terraform/envs/dev/01-resource-groups

terraform destroy \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars
```

**Blocked while children exist.** `terraform destroy` refuses if any
resource lives in these RGs — that means every downstream module
(`02-networking` through `12-monitoring`) must be destroyed FIRST, in
reverse order. See the destroy-order note in
[`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md) §4.

No post-destroy purge needed (RGs have no soft-delete window).

## Reprovision

Same commands as **Provision** — `terraform init` is idempotent, and RG names
are reusable immediately after destroy.

## Notes

- No `terraform.tfvars` values needed. The file exists only so the scaffolding
  matches every other module.
- The child module's set of purposes (`platform`, `network`, `data`, `app`,
  `observability`) is fixed on purpose. Adding one is a breaking change that
  every downstream module has to acknowledge.
