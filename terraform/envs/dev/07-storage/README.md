# 07-storage (envs/dev)

Root Terraform config that provisions the shared Storage Account for the
`dev` environment, one blob container per microservice, and the single RBAC
role assignment (`Storage Blob Data Contributor`) granted to the shared
UAMI. State lives at key `storage/terraform.tfstate` in the backend blob
container.

Wraps [`../../../modules/storage/`](../../../modules/storage/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads `rg_data_name`
  from its remote state.
- Module 04 (`04-managed-identities`) applied — this root reads
  `uami_app_principal_id` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env`, `location` and `apps`.
- Both `.tfvars` files are gitignored and are NOT in a fresh clone. Create them
  once — see [`INITIAL_SETUP.md`](../../../INITIAL_SETUP.md) § Terraform
  Variable Files. Tags are not among their values: they come from the committed
  [`../tags.json`](../tags.json), with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/envs/dev/07-storage

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=storage/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Account exists with the expected posture
az storage account list -g "rg-dev-data${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -o table
SA_NAME=$(terraform output -raw sa_name)
az storage account show -n "$SA_NAME" \
  --query "{name:name, sku:sku.name, kind:kind, tls:minimumTlsVersion, sharedKey:allowSharedKeyAccess, publicNet:publicNetworkAccess}" \
  -o table
# Expect sku=Standard_LRS, kind=StorageV2, tls=TLS1_2, sharedKey=false,
# publicNet=Enabled.

# Containers exist (one per app in var.apps)
az storage container list \
  --account-name "$SA_NAME" \
  --auth-mode login \
  --query "[].name" -o tsv
# Expect one row per app in ../env.tfvars `apps`.

# RBAC assignment granted to the shared UAMI
UAMI_PRINCIPAL=$(cd ../04-managed-identities && terraform output -raw uami_app_principal_id)
az role assignment list \
  --scope "$(terraform output -raw sa_id)" \
  --assignee "$UAMI_PRINCIPAL" \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
# Expect one row: Storage Blob Data Contributor at the storage account scope.
```

Note on `az storage container list --auth-mode login`: with
`shared_access_key_enabled = false`, the classic key-based auth path is
disabled. `--auth-mode login` uses the Azure CLI's AAD session, which
requires your user (or the CI SP) to have `Storage Blob Data Reader` or
higher on the account. If you get a 403, either `az login` as a user
with data access or grant your CLI principal the reader role.

Read the outputs Terraform will hand to downstream modules:

```bash
terraform output sa_id
terraform output sa_name
terraform output sa_primary_blob_endpoint
terraform output container_names
```

## Destroy

```bash
cd terraform/envs/dev/07-storage

terraform destroy
```

No post-destroy purge needed — the SA name is released immediately (no
account-level soft-delete tombstone). Blob soft delete is 2 days, but only
matters for individual blobs — the account itself is gone.

**Order matters.** Container Apps (module 11) read/write blobs via the
shared UAMI. Destroy module 11 first — otherwise running apps will see
403s the moment the RBAC assignment (or the SA) disappears.

## Reprovision

Same commands as **Provision**. The `random_id` suffix is keyed on `env`,
so reprovisioning the same env lands on a fresh name (`stdevapp<newhex>`).

## Notes

- No `terraform.tfvars` values needed, and no file needed either. Nothing is
  passed unconditionally any more: `terraform.tfvars` is auto-loaded when
  present, and every value can come from a `TF_VAR_*` environment variable
  instead. See
  [INITIAL_SETUP](../../../INITIAL_SETUP.md#terraform-environment).
- SKU (`Standard_LRS`), kind (`StorageV2`), and dev safety toggles are
  hard-coded in the child module (`modules/storage/main.tf`). Change there
  if you need to move to ZRS/GRS or enable network isolation.
- Container creation goes through the ARM control plane (`azapi_resource`)
  because `shared_access_key_enabled = false` disables the data-plane
  create path that `azurerm_storage_container` uses. See the child module
  README for why.
- No private endpoint yet — the `privatelink.blob.core.windows.net` zone
  provisioned by module 02 is available but unused. Adding a PE later
  is a small change; see the child module README.
- **`storage_use_azuread = true` + Terraform SP RBAC.** The provider
  block sets `storage_use_azuread = true` so the azurerm provider's
  post-create data-plane wait on the SA uses AAD instead of shared keys
  (which are disabled). To make that AAD call succeed, this root also
  grants the Terraform SP `Storage Blob Data Contributor` at the data
  RG scope, then waits 60s for RBAC to propagate before creating the
  SA. Without this dance, `azurerm_storage_account` create fails with
  `Key based authentication is not permitted on this storage account`.
  The grant lives in this root (not the child module) because it's a
  concern of *how the caller authenticates*, not of the storage design.
