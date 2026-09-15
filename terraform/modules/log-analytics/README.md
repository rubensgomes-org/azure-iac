# modules/log-analytics

Child Terraform module that provisions one Log Analytics Workspace per
environment. Consumed by the Container App Environment (module 10),
Application Insights (module 12), and any downstream diagnostic-settings
block that ships logs here.

Called by `terraform/roots/03-log-analytics/`. State is owned by the
caller — this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `azurerm_log_analytics_workspace` | `log-<workload>-<env>` | SKU `PerGB2018`, 30-day retention. |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `env` | `string` | yes | Baked into the workspace name and the random-suffix keeper. `^[a-z][a-z0-9]{1,9}$`. |
| `location` | `string` | yes | Azure region. Must match the RG's location. |
| `resource_group_name` | `string` | yes | RG that holds the workspace. Caller passes `rg-<workload>observability-<env>` (from module 01's remote state). |
| `tags` | `map(string)` | no | Merged with `component = "log-analytics"`. |

## Outputs

- `law_id` — full Azure Resource ID (`/subscriptions/.../workspaces/log-...`)
- `law_name`
- `law_workspace_id` — customer_id GUID; for tools that talk to the ingestion/query endpoints (CAE consumes `law_id` instead)
- `law_primary_shared_key` — sensitive; legacy agent auth
- `law_location`

## Design decisions

- **SKU `PerGB2018`.** Modern pay-as-you-go. Legacy SKUs (Free, Standalone,
  PerNode) are deprecated and cannot be selected on new workspaces.
- **30-day retention.** Minimum for PerGB2018 and enough for a playground.
  Bumping past 30 costs extra per-GB per-day.
- **No `daily_quota_gb`.** A hard quota silently drops ingestion once hit —
  worse than a small surprise bill for a learning env. Set cost alerts in
  Azure Budgets instead.
- **No random suffix in the name.** `log-<workload>-<env>` is deterministic, so
  it can be derived without reading state. The cost: LAW names go into a
  soft-delete recycle bin per RG for 14 days, and a destroy+recreate inside that
  window asks for the blocked name. Release it with
  `az monitor log-analytics workspace delete --force`, or recover the old
  workspace with `... workspace recover`. See
  [NAMING.md](../../../docs/NAMING.md#soft-delete-is-now-an-operational-concern).
- **Sensitive output `law_primary_shared_key`.** The passwordless model
  doesn't need it, but some downstream integrations (e.g. Container App
  Environment on older azurerm versions) still expect a key at
  resource-config time. Exposed here rather than re-fetching from the
  workspace resource in every consumer.
