# 04-managed-identities (terraform/roots)

Root Terraform config that provisions the single shared User-Assigned
Managed Identity used by every microservice in the ACA environment. State
lives at key `managed-identities/terraform.tfstate` in the backend blob
container.

Wraps [`../../modules/managed-identities/`](../../modules/managed-identities/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_platform_name` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../../envs/<env>/env.tfvars` populated with `env` and `location`.
- `env.tfvars` is gitignored and is NOT in a fresh clone. Every value in it can
  come from a `TF_VAR_*` export instead, which is how CI runs and the simpler
  local setup — see
  [`INITIAL_SETUP.md`](../../../docs/INITIAL_SETUP.md) § Terraform Variable
  Files. Tags are not among its values: they come from the committed
  `envs/<env>/tags.json`, with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/roots/04-managed-identities

terraform init \
  -backend-config=../../envs/<env>/backend.hcl \
  -backend-config="key=managed-identities/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# The UAMI exists
az identity show -g "rg-${TF_VAR_workload:-rgomes}platform-${TF_VAR_env:-lab}" -n id-${TF_VAR_workload:-rgomes}app-${TF_VAR_env:-lab} \
  --query "{name:name, clientId:clientId, principalId:principalId, tenantId:tenantId}" \
  -o table

# Terraform outputs match Azure state
terraform output uami_app_id
terraform output uami_app_client_id
terraform output uami_app_principal_id
```

## Destroy

```bash
cd terraform/roots/04-managed-identities

terraform destroy
```

**Blocked while RBAC assignments or attached apps still reference this
UAMI.** The role assignments in modules 05/06/07/08 name this UAMI as
their `principal_id`, and every Container App in module 11 attaches it via
`identity_ids`. Destroy those modules first — the reverse of the
dependency order in [`docs/MODULES_DEPENDENCY.md`](../../../docs/MODULES_DEPENDENCY.md).

No post-destroy purge needed. Deleting a UAMI also deletes its Entra
service principal — the `principal_id` is not held in a soft-delete
window. Reprovisioning creates a fresh `principal_id`, which invalidates
every RBAC assignment that referenced the old one; that's why role
assignments live in the downstream modules that recreate on reprovision,
not here.

## Reprovision

Same commands as **Provision** — `terraform init` is idempotent.

## Notes

- No `terraform.tfvars` values needed — and do not create the file. This root
  is shared by every environment, and Terraform auto-loads `terraform.tfvars`
  from the directory it runs in, so a file here would apply to `dev`, `lab` and
  anything after them alike, outranking the `TF_VAR_*` that was supposed to
  carry the difference. `make check-tfvars` refuses one. Every value comes from
  a `TF_VAR_*` environment variable; see
  [INITIAL_SETUP](../../../docs/INITIAL_SETUP.md#terraform-environment).
- The set of identities is fixed at ONE (`id-<workload>app-<env>`). Per-app
  identities are explicitly out of scope.
- Every downstream RBAC role assignment lives in the module that owns the
  scope (KV, ACR, SA, SB). This module publishes only the identifiers.
