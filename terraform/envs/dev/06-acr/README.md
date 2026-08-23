# 06-acr (envs/dev)

Root Terraform config that provisions the shared Azure Container Registry for
the `dev` environment plus the single RBAC role assignment (`AcrPull`)
granted to the shared UAMI. State lives in `tfstate/acr/terraform.tfstate`
on the bootstrap storage account.

Wraps [`../../../modules/acr/`](../../../modules/acr/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_platform_name` from its remote state.
- Module 04 (`04-managed-identities`) applied — this root reads
  `uami_app_principal_id` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env`, `location`, `tags`.

## Provision

```bash
cd terraform/envs/dev/06-acr

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=acr/terraform.tfstate"

terraform plan \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Registry exists with the expected posture
az acr list -g rg-dev-platform -o table
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

terraform destroy \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars
```

No post-destroy purge needed — Basic-SKU ACR has no soft-delete concept.
The name is released immediately and the random suffix regenerates on the
next apply, so name collisions are impossible.

**Order matters.** Container Apps (module 11) pull images from this
registry using the shared UAMI. Destroy module 11 first — otherwise the
app deployment holds an image reference and the registry destroy will
fail (or, worse, succeed and break running apps).

## Reprovision

Same commands as **Provision**. The `random_id` suffix is keyed on `env`,
so the same env reprovisioning lands on a fresh name (`acrdev<newhex>`).

See [`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md) §8
for the reprovision shortcut.

## Notes

- No `terraform.tfvars` values needed. Scaffolding consistency only.
- SKU (`Basic`), `admin_enabled = false`, and public-network posture are
  hard-coded in the child module (`modules/acr/main.tf`). Change there if
  you need to upgrade to Premium or add a private endpoint.
- No image-pushing setup here. CI pushes with an ad-hoc token, or you
  `az acr login` from a workstation and `docker push`. Adding push
  permission to the shared UAMI would let a compromised app overwrite
  images — deliberately left out.
