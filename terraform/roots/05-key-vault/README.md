# 05-key-vault (terraform/roots)

Root Terraform config that provisions the shared Key Vault for the target
environment plus the single RBAC role assignment (`Key Vault Secrets User`)
granted to the shared UAMI. State lives at key `key-vault/terraform.tfstate`
in the backend blob container.

Wraps [`../../modules/key-vault/`](../../modules/key-vault/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_platform_name` from its remote state.
- Module 04 (`04-managed-identities`) applied — this root reads
  `uami_app_principal_id` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../../envs/<env>/env.tfvars` populated with `env`, `location` and `prefix`.
- `env.tfvars` is gitignored and is NOT in a fresh clone. Every value in it can
  come from a `TF_VAR_*` export instead, which is how CI runs and the simpler
  local setup — see
  [`INITIAL_SETUP.md`](../../../docs/INITIAL_SETUP.md) § Terraform Variable
  Files. Tags are not among its values: they come from the committed
  `envs/<env>/tags.json`, with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/roots/05-key-vault

terraform init \
  -backend-config=../../envs/<env>/backend.hcl \
  -backend-config="key=key-vault/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Vault exists and is provisioned
az keyvault list -g "rg-${TF_VAR_workload:-rgomes}platform-${TF_VAR_env:-lab}" -o table
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
cd terraform/roots/05-key-vault

# Capture the name BEFORE destroy — needed for the purge below.
KV_NAME=$(terraform output -raw kv_name)

terraform destroy

# Post-destroy purge — required because we set purge_protection_enabled = false
# and the vault sits in a 7-day soft-delete window after destroy. The name is
# deterministic (kv-<workload>-<env>), so this is the ONLY name the next apply
# will ask for: skip the purge and the reprovision fails for 7 days.
az keyvault purge --name "$KV_NAME" --location centralus
```

**Order matters.** If the vault ever gets referenced by a downstream module
(e.g. a private-endpoint DNS record, or later a secret consumed by
Container Apps), destroy those modules first. As of the current estate,
no downstream module writes to KV directly, so `terraform destroy` here
should succeed as long as no manually-created resources reference it.

## Reprovision

Same commands as **Provision**. If you skipped the `az keyvault purge` step
above, `terraform apply` fails on the same name (soft-delete tombstone). Since
the CAF rename there is no random suffix to route around it, so there are only
two options:

1. Run `az keyvault purge --name kv-<workload>-<env> --location centralus`
   first. This is the recommended path, and `make destroy` already does it.
2. Wait 7 days for the tombstone to expire, then reprovision.

See [NAMING.md](../../../docs/NAMING.md#soft-delete-is-now-an-operational-concern).

## Notes

- No `terraform.tfvars` values needed — and do not create the file. This root
  is shared by every environment, and Terraform auto-loads `terraform.tfvars`
  from the directory it runs in, so a file here would apply to `dev`, `lab` and
  anything after them alike, outranking the `TF_VAR_*` that was supposed to
  carry the difference. `make check-tfvars` refuses one. Every value comes from
  a `TF_VAR_*` environment variable; see
  [INITIAL_SETUP](../../../docs/INITIAL_SETUP.md#terraform-environment).
- SKU, RBAC mode, and dev safety toggles are hard-coded in the child
  module (`modules/key-vault/main.tf`). Change there if you need to.
- No private endpoint yet — the `privatelink.vaultcore.azure.net` zone
  provisioned by module 02 is available but unused. Adding a PE later
  is a small change; see the child module README.
