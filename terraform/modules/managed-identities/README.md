# modules/managed-identities

Child Terraform module that provisions the **single shared** User-Assigned
Managed Identity used by every microservice in the ACA environment. Every
downstream module that needs passwordless auth reads this UAMI's IDs via
`data.terraform_remote_state`.

Called by `terraform/envs/dev/04-managed-identities/`. State is owned by the
caller — this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `azurerm_user_assigned_identity` | `id-<env>-app` | Lives in `rg-<env>-platform`. |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `env` | `string` | yes | Baked into the UAMI name. `^[a-z][a-z0-9]{1,9}$`. |
| `location` | `string` | yes | Azure region. Must match the RG's location. |
| `resource_group_name` | `string` | yes | RG that holds the UAMI. Caller passes `rg-<env>-platform` (from module 01's remote state). |
| `tags` | `map(string)` | no | Merged with `component = "managed-identity"`. |

## Outputs

- `uami_app_id` — full Azure Resource ID (for `identity_ids`)
- `uami_app_name` — the identity name (also the PG AAD principal name)
- `uami_app_principal_id` — Entra object ID (for RBAC grants)
- `uami_app_client_id` — OAuth client ID (for `AZURE_CLIENT_ID` env var)
- `uami_app_tenant_id`
- `uami_app_location`

## Design decisions

- **One UAMI, not per-app.** Every microservice shares this identity. Simpler
  RBAC, uniform blast-radius. See `docs/PROVISIONING_PLAN.md` §12 for the
  trade-off writeup.
- **Lives in `rg-<env>-platform`.** Long-lived and shared across workloads —
  belongs with Key Vault and ACR, not with the fast-iterating app RG.
- **No random suffix.** UAMI names are scoped to their RG, not globally
  unique. `id-<env>-app` is stable and destroy+recreate-safe.

## Downstream consumers

Every module below reads `uami_app_*` outputs via
`data.terraform_remote_state`:

| Module | What it does with the UAMI |
|--------|----------------------------|
| 05 key-vault | `Key Vault Secrets User` role assignment at vault scope |
| 06 acr | `AcrPull` role assignment at ACR scope |
| 07 storage | `Storage Blob Data Contributor` role assignment at SA scope |
| 08 service-bus | `Data Sender` + `Data Receiver` role assignments at namespace scope |
| 09 postgresql | Registers UAMI as an in-DB AAD principal; grants `CONNECT` on every app DB |
| 11 container-apps | Attaches to every Container App via `identity_ids`; sets `AZURE_CLIENT_ID` env var |
