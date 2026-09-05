# modules/log-analytics

Child Terraform module that provisions one Log Analytics Workspace per
environment. Consumed by the Container App Environment (module 10),
Application Insights (module 12), and any downstream diagnostic-settings
block that ships logs here.

Called by `terraform/envs/dev/03-log-analytics/`. State is owned by the
caller — this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `random_id` | `suffix` | 4-hex-char suffix, keyed on `env`. |
| `azurerm_log_analytics_workspace` | `log-<env>-<random>` | SKU `PerGB2018`, 30-day retention. |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `env` | `string` | yes | Baked into the workspace name and the random-suffix keeper. `^[a-z][a-z0-9]{1,9}$`. |
| `location` | `string` | yes | Azure region. Must match the RG's location. |
| `resource_group_name` | `string` | yes | RG that holds the workspace. Caller passes `rg-<env>-observability` (from module 01's remote state). |
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
- **Random suffix in the name.** LAW names go into a 30-day soft-delete
  recycle bin per RG. A stable random suffix lets destroy+recreate land on
  a fresh name without waiting out the block.
- **Sensitive output `law_primary_shared_key`.** The passwordless model
  doesn't need it, but some downstream integrations (e.g. Container App
  Environment on some azurerm 4.x versions) still expect a key at
  resource-config time. Exposed here rather than re-fetching from the
  workspace resource in every consumer.
