# 06-acr (envs/dev)

Root Terraform config that provisions the shared Azure Container Registry
for the `dev` environment plus the single RBAC role assignment (`AcrPull`)
granted to the shared UAMI. State lives at key `acr/terraform.tfstate` in
the backend blob container.

Wraps [`../../../modules/acr/`](../../../modules/acr/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_platform_name` from its remote state.
- Module 04 (`04-managed-identities`) applied — this root reads
  `uami_app_principal_id` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env` and `location`.
- `./terraform.tfvars` populated with `acr_name` (dev: `rubensdevacr`).
  Required; this root has no default for it.
- Both `.tfvars` files are gitignored and are NOT in a fresh clone. Create them
  once — see [`INITIAL_SETUP.md`](../../../INITIAL_SETUP.md) § Terraform
  Variable Files. Tags are not among their values: they come from the committed
  [`../tags.json`](../tags.json), with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/envs/dev/06-acr

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=acr/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Registry exists with the expected posture
az acr list -g "rg-dev-platform${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -o table
ACR_NAME=$(terraform output -raw acr_name)
az acr show -n "$ACR_NAME" \
  --query "{name:name, sku:sku.name, adminEnabled:adminUserEnabled, publicNet:publicNetworkAccess, loginServer:loginServer}" \
  -o table
# Expect sku = Basic, adminEnabled = false, publicNet = Enabled.

# RBAC assignment granted to the shared UAMI
UAMI_PRINCIPAL=$(cd ../04-managed-identities && terraform output -raw uami_app_principal_id)
az role assignment list \
  --scope "$(terraform output -raw acr_id)" \
  --assignee "$UAMI_PRINCIPAL" \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
# Expect one row: AcrPull at the registry scope.
```

Read the outputs Terraform will hand to downstream modules:

```bash
terraform output acr_id
terraform output acr_name
terraform output acr_login_server
```

## Destroy

```bash
cd terraform/envs/dev/06-acr

terraform destroy
```

No post-destroy purge needed — Basic-SKU ACR has no soft-delete concept.
The name is released immediately, so the same `acr_name` can be applied
again straight away.

**Order matters.** Container Apps (module 11) pull images from this
registry using the shared UAMI. Destroy module 11 first — otherwise the
app deployment holds an image reference and the registry destroy will
fail (or, worse, succeed and break running apps).

## Reprovision

Same commands as **Provision**, and the registry comes back with the SAME
name — `acr_name` is a fixed input (`rubensdevacr` in dev), not a generated
one. Basic SKU has no soft-delete, so the name is released on destroy and
immediately reusable. Image *contents* are not recoverable; only the name is.

## Notes

- `terraform.tfvars` holds `acr_name`. It lives there rather than in
  `../env.tfvars` because the registry name is one module's concern, not a
  value shared by all twelve roots. Changing it renames the registry, which
  azurerm implements as destroy-and-recreate — every image is lost.
- SKU (`Basic`), `admin_enabled = false`, and public-network posture are
  hard-coded in the child module (`modules/acr/main.tf`). Change there if
  you need to upgrade to Premium or add a private endpoint.
- No image-pushing setup here. CI pushes with an ad-hoc token, or you
  `az acr login` from a workstation and `docker push`. Adding push
  permission to the shared UAMI would let a compromised app overwrite
  images — deliberately left out.
