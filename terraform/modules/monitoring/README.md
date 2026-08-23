# modules/monitoring

Reusable child module that provisions the env's observability stack:

- **Application Insights** — workspace-based, backed by the shared Log
  Analytics Workspace (module 03). Apps read the connection string via
  the standard `APPLICATIONINSIGHTS_CONNECTION_STRING` env var.
- **Action Group** — one email receiver named `owner`. Alert rules are
  intentionally NOT declared here; per-workload SLOs land in a follow-on.
- **Five diagnostic settings** — Key Vault, ACR, Storage (blob subresource),
  Service Bus, PostgreSQL — all sinking `allLogs` + `AllMetrics` into
  the same shared LAW. A single Kusto query spans the estate.

Container Apps stdout/stderr already streams into LAW via the environment
wired in module 10, so no `container-apps` diagnostic setting is needed
here.

## Contract

**Inputs** (see `variables.tf` for full descriptions and validation):

| Name                        | Type        | Description                                                        |
|-----------------------------|-------------|--------------------------------------------------------------------|
| `env`                       | string      | Env token, baked into `appi-<env>` and `ag-<env>-ops`.             |
| `location`                  | string      | Azure region for App Insights + action group.                      |
| `resource_group_name`       | string      | `rg-<env>-observability` (from module 01).                         |
| `log_analytics_workspace_id`| string      | `law_id` (from module 03). Backs App Insights AND is the diag sink. |
| `action_group_email`        | string      | Email receiver for the `owner` alert channel. Regex-validated.     |
| `key_vault_id`              | string      | `kv_id` (from module 05).                                          |
| `acr_id`                    | string      | `acr_id` (from module 06).                                         |
| `storage_account_id`        | string      | `sa_id` (from module 07). Diag setting attaches at blob subresource.|
| `service_bus_namespace_id`  | string      | `sb_namespace_id` (from module 08).                                |
| `postgresql_server_id`      | string      | `pg_server_id` (from module 09).                                   |
| `tags`                      | map(string) | Merged with `component` per resource.                              |

**Outputs:**

| Name                     | Description                                                          |
|--------------------------|----------------------------------------------------------------------|
| `ai_id`                  | App Insights resource ID.                                            |
| `ai_name`                | `appi-<env>`.                                                        |
| `ai_app_id`              | App Insights `app_id` GUID.                                          |
| `ai_instrumentation_key` | Legacy key (sensitive).                                              |
| `ai_connection_string`   | Preferred telemetry carrier (sensitive).                             |
| `action_group_ids`       | Map short-name → full ID. One entry today (`ops`).                   |
| `diagnostic_setting_ids` | Map target → diag setting ID. Informational; no downstream consumer. |

## Design decisions

- **Workspace-based App Insights.** Classic (non-workspace) AI is
  retired for new resources. Workspace-based stores telemetry in LAW
  tables — same billing bucket as container logs, Kusto queryable in
  one place.
- **`category_group = "allLogs"`** on every diag setting. Future-proof
  against new categories Azure adds. Pin to individual categories only
  when trimming ingestion cost becomes a real concern.
- **Diag setting at storage's blob subresource, not the account.** Log
  categories only surface at `<sa_id>/blobServices/default`. Account-
  level metrics (Transaction, Capacity) can be added as a second setting
  if we care about them later.
- **No alert rules.** Rule semantics are workload-specific. Wiring a
  spurious alert during bring-up teaches people to mute alerts. The
  action group + `action_group_ids` output is the plumbing; alert
  resources live per-app in a follow-on.
- **App Insights retention / sampling not overridden.** Inherits both
  from the LAW. Set at the workspace level (module 03) if the whole
  estate needs to change; per-AI overrides would drift the two apart.

## Usage

Called from `envs/dev/12-monitoring/main.tf`. See that root's
`README.md` for the copy-paste apply/verify/destroy sequence and the
Kusto snippets that prove the diag settings are actually landing rows
in LAW.
