# 03-log-analytics (envs/dev)

Root Terraform config that provisions the shared Log Analytics Workspace for
the `dev` environment. State lives at key `log-analytics/terraform.tfstate`
in the backend blob container.

Wraps [`../../../modules/log-analytics/`](../../../modules/log-analytics/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_observability_name` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env` and `location`.
- Both `.tfvars` files are gitignored and are NOT in a fresh clone. Create them
  once — see [`INITIAL_SETUP.md`](../../../INITIAL_SETUP.md) § Terraform
  Variable Files. Tags are not among their values: they come from the committed
  [`../tags.json`](../tags.json), with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/envs/dev/03-log-analytics

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=log-analytics/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Workspace exists and is provisioned
az monitor log-analytics workspace list -g "rg-dev-observability${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -o table
# Expect one row: log-dev-<random>, provisioningState = Succeeded.

# Sanity-check SKU + retention
LAW_NAME=$(terraform output -raw law_name)
az monitor log-analytics workspace show \
  -g "rg-dev-observability${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -n "$LAW_NAME" \
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
cd terraform/envs/dev/03-log-analytics

terraform destroy
```

**Blocked while downstream consumers exist.** Any Container App Environment,
Application Insights component, or diagnostic-settings block that points at
this workspace must be destroyed first.

**Soft-delete note.** Deleted workspace names are held for 30 days per RG.
The random suffix in `log-<env>-<random>` sidesteps this — on
reprovision, `random_id` regenerates and Terraform requests a fresh name.
No manual purge needed, unless you specifically want the old name back
(in which case wait 30 days or run `az monitor log-analytics workspace
delete --force`).

## Reprovision

Same commands as **Provision** — `terraform init` is idempotent.

## Notes

- No `terraform.tfvars` values needed, and no file needed either. Nothing is
  passed unconditionally any more: `terraform.tfvars` is auto-loaded when
  present, and every value can come from a `TF_VAR_*` environment variable
  instead. See
  [INITIAL_SETUP](../../../INITIAL_SETUP.md#terraform-environment).
- SKU and retention are hard-coded in the child module
  (`modules/log-analytics/main.tf`). Change there if you need to.
- `daily_quota_gb` is deliberately unset. A hard quota silently drops
  ingestion once hit — set cost alerts in Azure Budgets instead.
