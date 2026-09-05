# modules/storage

Child Terraform module that provisions the shared Azure Storage Account per
environment, one blob container per microservice, and the single RBAC role
assignment (`Storage Blob Data Contributor`) that lets the shared UAMI
read/write blobs.

Called by `terraform/envs/dev/07-storage/`. State is owned by the caller —
this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `random_id` | `suffix` | 4-hex-char suffix; keyed on `env`. |
| `azurerm_storage_account` | `st<env>app<random>` | Standard_LRS, StorageV2, TLS 1.2, `shared_access_key_enabled = false`, 2-day soft delete on blobs + containers. |
| `azurerm_role_assignment` | `Storage Blob Data Contributor` for UAMI | Scope: storage account. |
| `azapi_resource` | `container` per `var.apps` | ARM control plane; `publicAccess = None`. |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `env` | `string` | yes | Baked into name and random keeper. `^[a-z][a-z0-9]{1,9}$`. |
| `location` | `string` | yes | Azure region. Must match the RG's location. |
| `resource_group_name` | `string` | yes | Caller passes `rg-<env>-data` (from module 01). |
| `uami_principal_id` | `string` | yes | `principal_id` of the shared UAMI (from module 04). |
| `apps` | `list(string)` | no | Names of microservices. One container per name. Default `[]`. |
| `tags` | `map(string)` | no | Merged with `component = "storage"`. |

## Outputs

- `sa_id` — full Azure Resource ID
- `sa_name` — account name
- `sa_primary_blob_endpoint` — `https://<name>.blob.core.windows.net/`
- `sa_location`
- `sa_role_assignment_id`
- `container_names` — map `{ <app> => <container-name> }`
- `container_ids` — map `{ <app> => <full-resource-id> }`

## Design decisions

- **Standard_LRS.** Cheapest replication tier. Single-region durability is
  enough for a playground. Move to `Standard_ZRS` (zone-redundant, still
  cheap) or `Standard_GRS` (cross-region) as a one-line `local` change.
- **StorageV2 general-purpose.** Blob + File + Queue + Table under one
  account — future-proofs against needing another storage kind.
- **`shared_access_key_enabled = false`.** No account keys anywhere. All
  data-plane access is AAD-authenticated. Removing this contradicts the
  passwordless model — apps would suddenly be allowed to use connection
  strings.
- **Public network enabled.** Playground posture, matches ACR/KV. Move to
  private endpoint (zone `privatelink.blob.core.windows.net` from module
  02) if we want network isolation.
- **`allow_nested_items_to_be_public = false`.** Even if a container is
  ever created with `publicAccess != None`, individual blobs stay private.
  Defense in depth.
- **Soft delete = 2 days (both blob + container).** Shortest tolerable
  "oops" window. 0 disables recovery; higher hoards state and cost.
- **Containers via `azapi_resource` (ARM plane), not
  `azurerm_storage_container` (data plane).** With shared keys disabled,
  the azurerm container resource would need the Terraform SP to hold
  `Storage Blob Data Contributor` on the SA plus a 30-60s wait for RBAC
  propagation. `azapi_resource` uses `Microsoft.Storage/.../containers`
  ARM API, which the SP already has Contributor on via bootstrap — no
  extra grant, no wait.
- **`Storage Blob Data Contributor` (not Reader).** Apps write blobs, not
  just read. Scope is the SA — every container inherits. Tighten to
  per-container scope later if isolation matters.
- **RBAC scope = storage account, not container.** Dev-friendly: one
  assignment covers every current and future container. The trade-off is a
  blast radius shared across every app.

## Not dependencies

Modules 02 (network) and 05 (Key Vault) read like storage dependencies,
but neither has a structural dep in the current design:

- **02 network:** No private endpoint in this iteration. If we add a PE,
  wire remote state to module 02 for `subnet_pe_id` and `dns_zone_blob_id`.
- **05 Key Vault:** No customer-managed key for encryption-at-rest — the
  Microsoft-managed key covers dev. No account key to stash (they're
  disabled). If we add CMK later, wire remote state to module 05.

## Downstream consumers

- **Container Apps (module 11):** each `azurerm_container_app` gets env
  vars `STORAGE_ACCOUNT_NAME = <sa_name>` and (per-app)
  `STORAGE_CONTAINER_NAME = container_names[<app>]`. Apps compose the
  blob URL and authenticate via `DefaultAzureCredential` — no keys,
  no SAS.
