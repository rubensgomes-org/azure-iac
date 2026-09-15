# 03-log-analytics (terraform/roots)

Root Terraform config that provisions the shared Log Analytics Workspace for
the target environment. State lives at key `log-analytics/terraform.tfstate`
in the backend blob container.

Wraps [`../../modules/log-analytics/`](../../modules/log-analytics/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_observability_name` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../../envs/<env>/env.tfvars` populated with `env` and `location`.
- `env.tfvars` is gitignored and is NOT in a fresh clone. Every value in it can
  come from a `TF_VAR_*` export instead, which is how CI runs and the simpler
  local setup — see
  [`INITIAL_SETUP.md`](../../../docs/INITIAL_SETUP.md) § Terraform Variable
  Files. Tags are not among its values: they come from the committed
  `envs/<env>/tags.json`, with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/roots/03-log-analytics

terraform init \
  -backend-config=../../envs/<env>/backend.hcl \
  -backend-config="key=log-analytics/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Workspace exists and is provisioned
az monitor log-analytics workspace list -g "rg-${TF_VAR_workload:-rgomes}observability-${TF_VAR_env:-lab}" -o table
# Expect one row: log-${TF_VAR_workload:-rgomes}-${TF_VAR_env:-lab}, provisioningState = Succeeded.

# Sanity-check SKU + retention
LAW_NAME=$(terraform output -raw law_name)
az monitor log-analytics workspace show \
  -g "rg-${TF_VAR_workload:-rgomes}observability-${TF_VAR_env:-lab}" -n "$LAW_NAME" \
  --query "{name:name, sku:sku.name, retentionDays:retentionInDays}" -o table
# Expect sku = pergb2018, retentionDays = 30.
```

Read the outputs Terraform will hand to downstream modules:

```bash
terraform output law_id
terraform output law_workspace_id
terraform output -raw law_primary_shared_key   # sensitive
```

## Destroy

```bash
cd terraform/roots/03-log-analytics

terraform destroy
```

**Blocked while downstream consumers exist.** Any Container App Environment,
Application Insights component, or diagnostic-settings block that points at
this workspace must be destroyed first.

**Soft-delete note — read before reprovisioning.** Deleted workspace names are
held in a recycle bin per RG for 14 days. `log-<workload>-<env>` is fully
deterministic since the CAF rename, so a rebuild inside that window asks for
the one name that is blocked and the apply fails. This module used to append a
`random_id` precisely to sidestep that; it no longer does. Release the name
with:

```bash
az monitor log-analytics workspace delete \
  --resource-group "rg-${TF_VAR_workload:-rgomes}observability-${TF_VAR_env:-lab}" \
  --workspace-name "log-${TF_VAR_workload:-rgomes}-${TF_VAR_env:-lab}" \
  --force --yes
```

Or `az monitor log-analytics workspace recover ...` if you want the old
workspace and its data back. See
[NAMING.md](../../../docs/NAMING.md#soft-delete-is-now-an-operational-concern).

## Reprovision

Same commands as **Provision** — `terraform init` is idempotent.

## Notes

- No `terraform.tfvars` values needed — and do not create the file. This root
  is shared by every environment, and Terraform auto-loads `terraform.tfvars`
  from the directory it runs in, so a file here would apply to `dev`, `lab` and
  anything after them alike, outranking the `TF_VAR_*` that was supposed to
  carry the difference. `make check-tfvars` refuses one. Every value comes from
  a `TF_VAR_*` environment variable; see
  [INITIAL_SETUP](../../../docs/INITIAL_SETUP.md#terraform-environment).
- SKU and retention are hard-coded in the child module
  (`modules/log-analytics/main.tf`). Change there if you need to.
- `daily_quota_gb` is deliberately unset. A hard quota silently drops
  ingestion once hit — set cost alerts in Azure Budgets instead.
