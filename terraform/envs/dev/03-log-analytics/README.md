# 03-log-analytics (envs/dev)

Root Terraform config that provisions the shared Log Analytics Workspace
for the `dev` environment. State lives in
`tfstate/log-analytics/terraform.tfstate` on the bootstrap storage account.

Wraps [`../../../modules/log-analytics/`](../../../modules/log-analytics/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_observability_name` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env`, `location`, `tags`.

## Provision

```bash
cd terraform/envs/dev/03-log-analytics

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=log-analytics/terraform.tfstate"

terraform plan \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Workspace exists and is provisioned
az monitor log-analytics workspace list -g rg-dev-observability -o table
# Expect one row: log-dev-<random>, provisioningState = Succeeded.

# Sanity-check SKU + retention
LAW_NAME=$(terraform output -raw law_name)
az monitor log-analytics workspace show \
  -g rg-dev-observability -n "$LAW_NAME" \
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

terraform destroy \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars
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

Same commands as **Provision** — `terraform init` is idempotent. See
[`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md) §8 for the
reprovision shortcut.

## Notes

- No `terraform.tfvars` values needed. Scaffolding consistency only.
- SKU and retention are hard-coded in the child module
  (`modules/log-analytics/main.tf`). Change there if you need to.
- `daily_quota_gb` is deliberately unset. A hard quota silently drops
  ingestion once hit — set cost alerts in Azure Budgets instead.
