# 12-monitoring (envs/dev)

Root Terraform config for the env's observability stack: Application
Insights (workspace-based, backed by the shared LAW from module 03), one
Action Group with an email receiver, and five diagnostic settings (KV, ACR,
Storage blob subresource, Service Bus, PostgreSQL) all sinking into the same
LAW. State lives at key `monitoring/terraform.tfstate` in the backend blob
container.

This is the last module in the dependency chain; once it applies, the
estate is complete. `make apply` and `make destroy` drive the whole
estate from the repo root.

Wraps [`../../../modules/monitoring/`](../../../modules/monitoring/README.md).

## Prerequisites

Modules **01, 03, 05, 06, 07, 08, and 09** applied. This root reads:

| From                       | Outputs consumed                     |
|----------------------------|--------------------------------------|
| 01-resource-groups         | `rg_observability_name`              |
| 03-log-analytics           | `law_id`                             |
| 05-key-vault               | `kv_id`                              |
| 06-acr                     | `acr_id`                             |
| 07-storage                 | `sa_id`                              |
| 08-service-bus             | `sb_namespace_id`                    |
| 09-postgresql              | `pg_server_id`                       |

Additional requirements:

- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`,
  `ARM_SUBSCRIPTION_ID` exported in the current shell.
- `../env.tfvars` populated with `env` and `location`.
- `./terraform.tfvars` populated with `action_group_email` — the address the
  action group notifies. Required; this root has no default for it.
- Both `.tfvars` files are gitignored and are NOT in a fresh clone. Create them
  once — see [`INITIAL_SETUP.md`](../../../INITIAL_SETUP.md) § Terraform
  Variable Files. Tags are not among their values: they come from the committed
  [`../tags.json`](../tags.json), with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/envs/dev/12-monitoring

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=monitoring/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

Apply time is ~30-60 seconds — App Insights + action group are quick,
and the five diagnostic settings are near-instant (metadata only, no
compute plane).

## Verify

```bash
# App Insights exists, provisioning state = Succeeded
az monitor app-insights component show \
  -g "rg-dev-observability${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -a appi-dev \
  --query "{name:name, kind:kind, state:provisioningState, workspaceId:workspaceResourceId}" \
  -o table
# Expect kind=web, state=Succeeded, workspaceId ends with /workspaces/log-dev-<random>.

# Action group exists
az monitor action-group list -g "rg-dev-observability${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -o table
# Expect one row: ag-dev-ops.

# Diagnostic settings landed on every target
for r in \
  $(cd ../05-key-vault && terraform output -raw kv_id) \
  $(cd ../06-acr        && terraform output -raw acr_id) \
  $(cd ../07-storage    && terraform output -raw sa_id)/blobServices/default \
  $(cd ../08-service-bus && terraform output -raw sb_namespace_id) \
  $(cd ../09-postgresql && terraform output -raw pg_server_id); do
  echo "=== $r ==="
  az monitor diagnostic-settings list --resource "$r" -o table
done
# Expect one setting named `diag-to-law` on each.

# Confirm rows land in LAW after ~5-10 minutes of real traffic
az monitor log-analytics query \
  --workspace "$(cd ../03-log-analytics && terraform output -raw law_workspace_id)" \
  --analytics-query "union AzureDiagnostics, AzureMetrics | where TimeGenerated > ago(1h) | summarize count() by ResourceType" \
  -o table
```

Sanity outputs from Terraform:

```bash
terraform output ai_connection_string   # sensitive — quote when passing to apps
terraform output action_group_ids       # map: ops → /subscriptions/.../actionGroups/ag-dev-ops
terraform output diagnostic_setting_ids # map: target → diag setting ID
```

## Destroy

```bash
cd terraform/envs/dev/12-monitoring

terraform destroy
```

Monitoring has no downstream — safe to destroy any time. Nothing purges
after destroy: App Insights, action groups, and diagnostic settings all
free their names immediately.

## Notes

- **Estate-wide Kusto queries.** Because every diagnostic setting sinks
  into the same LAW that already receives Container Apps stdout/stderr
  (module 10), a single query like
  `union AzureDiagnostics, ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h)`
  covers the whole estate.
- **App Insights connection string.** The recommended way to wire it
  into Container Apps is via a new env var `APPLICATIONINSIGHTS_CONNECTION_STRING`
  on module 11 (child module `container-apps`). Not wired today because
  Java / Spring Boot images aren't deployed yet — add when real apps
  land.
- **No alert rules.** Rule semantics are workload-specific. Wire per-app
  alerts against `action_group_ids.ops` once real SLOs exist. Adding
  spurious alerts during bring-up trains people to mute alerts, not fix
  them.
- **Nothing to purge.** Unlike Key Vault (soft-delete) or PostgreSQL
  (name-hold window), monitoring resources free their names on destroy.
