# 05-key-vault (envs/dev)

Root Terraform config that provisions the shared Key Vault for the `dev`
environment plus the single RBAC role assignment (`Key Vault Secrets User`)
granted to the shared UAMI. State lives in `tfstate/key-vault/terraform.tfstate`
on the bootstrap storage account.

Wraps [`../../../modules/key-vault/`](../../../modules/key-vault/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_platform_name` from its remote state.
- Module 04 (`04-managed-identities`) applied — this root reads
  `uami_app_principal_id` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env`, `location`, `prefix`, `tags`.

## Provision

```bash
cd terraform/envs/dev/05-key-vault

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=key-vault/terraform.tfstate"

terraform plan \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Vault exists and is provisioned
az keyvault list -g rg-dev-platform -o table
KV_NAME=$(terraform output -raw kv_name)
az keyvault show -n "$KV_NAME" \
  --query "{name:name, sku:properties.sku.name, rbac:properties.enableRbacAuthorization, purgeProt:properties.enablePurgeProtection, softDeleteDays:properties.softDeleteRetentionInDays}" \
  -o table
# Expect rbac = true, purgeProt = false/null, softDeleteDays = 7.

# RBAC assignment granted to the shared UAMI
UAMI_PRINCIPAL=$(cd ../04-managed-identities && terraform output -raw uami_app_principal_id)
az role assignment list \
  --scope "$(terraform output -raw kv_id)" \
  --assignee "$UAMI_PRINCIPAL" \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
# Expect one row: Key Vault Secrets User at the vault scope.
```

Read the outputs Terraform will hand to downstream modules:

```bash
terraform output kv_id
terraform output kv_name
terraform output kv_uri
```

## Destroy

```bash
cd terraform/envs/dev/05-key-vault

# Capture the name BEFORE destroy — needed for the purge below.
KV_NAME=$(terraform output -raw kv_name)

terraform destroy \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars

# Post-destroy purge — required because we set purge_protection_enabled = false
# and the vault sits in a 7-day soft-delete window after destroy. Purging lets
# us reprovision immediately (with a new random suffix) or reuse the same name.
az keyvault purge --name "$KV_NAME" --location eastus
```

**Order matters.** If the vault ever gets referenced by a downstream module
(e.g. a private-endpoint DNS record, or later a secret consumed by
Container Apps), destroy those modules first. As of the current estate,
no downstream module writes to KV directly, so `terraform destroy` here
should succeed as long as no manually-created resources reference it.

## Reprovision

Same commands as **Provision**. If you skipped the `az keyvault purge`
step above, `terraform apply` will fail on the same name (soft-delete
tombstone). Options:

1. Wait 7 days for the tombstone to expire, then reprovision.
2. Run `az keyvault purge --name <old-name> --location eastus` first.
3. Ignore — the random suffix regenerates on reprovision, so the new name
   won't collide with the tombstone. This is the recommended path.

See [`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md) §8
for the reprovision shortcut.

## Notes

- No `terraform.tfvars` values needed. Scaffolding consistency only.
- SKU, RBAC mode, and dev safety toggles are hard-coded in the child
  module (`modules/key-vault/main.tf`). Change there if you need to.
- No private endpoint yet — the `privatelink.vaultcore.azure.net` zone
  provisioned by module 02 is available but unused. Adding a PE later
  is a small change; see the child module README.
