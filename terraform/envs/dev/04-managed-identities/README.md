# 04-managed-identities (envs/dev)

Root Terraform config that provisions the single shared User-Assigned
Managed Identity used by every microservice in the ACA environment. State
lives in `tfstate/managed-identities/terraform.tfstate` on the bootstrap
storage account.

Wraps [`../../../modules/managed-identities/`](../../../modules/managed-identities/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_platform_name` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env`, `location`, `tags`.

## Provision

```bash
cd terraform/envs/dev/04-managed-identities

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=managed-identities/terraform.tfstate"

terraform plan \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# The UAMI exists
az identity show -g rg-dev-platform -n id-dev-app \
  --query "{name:name, clientId:clientId, principalId:principalId, tenantId:tenantId}" \
  -o table

# Terraform outputs match Azure state
terraform output uami_app_id
terraform output uami_app_client_id
terraform output uami_app_principal_id
```

## Destroy

```bash
cd terraform/envs/dev/04-managed-identities

terraform destroy \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars
```

**Blocked while RBAC assignments or attached apps still reference this
UAMI.** The role assignments in modules 05/06/07/08 name this UAMI as
their `principal_id`, and every Container App in module 11 attaches it via
`identity_ids`. Destroy those modules first — reverse order from
[`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md) §4.

No post-destroy purge needed. Deleting a UAMI also deletes its Entra
service principal — the `principal_id` is not held in a soft-delete
window. Reprovisioning creates a fresh `principal_id`, which invalidates
every RBAC assignment that referenced the old one; that's why role
assignments live in the downstream modules that recreate on reprovision,
not here.

## Reprovision

Same commands as **Provision** — `terraform init` is idempotent. See
[`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md) §8 for the
reprovision shortcut.

## Notes

- No `terraform.tfvars` values needed. Scaffolding consistency only.
- The set of identities is fixed at ONE (`id-<env>-app`). Per-app identities
  are explicitly out of scope. See `docs/PROVISIONING_PLAN.md` §12.
- Every downstream RBAC role assignment lives in the module that owns the
  scope (KV, ACR, SA, SB). This module publishes only the identifiers.
