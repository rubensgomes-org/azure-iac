# 02-networking (envs/dev)

Root Terraform config that provisions the VNet, three subnets, three NSGs,
and five private DNS zones for the `dev` environment. State lives at key
`networking/terraform.tfstate` in the backend blob container.

Wraps [`../../../modules/networking/`](../../../modules/networking/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_network_name` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env` and `location`.
- Both `.tfvars` files are gitignored and are NOT in a fresh clone. Create them
  once — see [`INITIAL_SETUP.md`](../../../INITIAL_SETUP.md) § Terraform
  Variable Files. Tags are not among their values: they come from the committed
  [`../tags.json`](../tags.json), with `TF_VAR_owner` overriding `owner`.

## Provision

```bash
cd terraform/envs/dev/02-networking

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=networking/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# VNet and subnets
az network vnet list -g "rg-dev-network${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -o table
az network vnet subnet list -g "rg-dev-network${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" --vnet-name vnet-dev -o table
# Expect: vnet-dev present; snet-dev-{app,pg,pe} listed with correct CIDRs.

# NSGs
az network nsg list -g "rg-dev-network${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -o table
# Expect: nsg-dev-{app,pg,pe} present.

# Private DNS zones
az network private-dns zone list -g "rg-dev-network${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -o table
# Expect 5 zones:
#   privatelink.vaultcore.azure.net
#   privatelink.blob.core.windows.net
#   privatelink.azurecr.io
#   privatelink.servicebus.windows.net
#   private.postgres.database.azure.com

# VNet links (one per zone)
for z in \
  privatelink.vaultcore.azure.net \
  privatelink.blob.core.windows.net \
  privatelink.azurecr.io \
  privatelink.servicebus.windows.net \
  private.postgres.database.azure.com; do
  az network private-dns link vnet list -g "rg-dev-network${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" --zone-name "$z" -o table
done
```

Read the outputs Terraform will hand to downstream modules:

```bash
terraform output vnet_id
terraform output subnet_app_id
terraform output subnet_pg_id
terraform output subnet_pe_id
terraform output private_dns_zones
```

## Destroy

```bash
cd terraform/envs/dev/02-networking

terraform destroy
```

**Blocked while delegated subnets are in use.** Delegated subnets refuse to
destroy while their delegated resource still exists:

- `snet-dev-app` blocks while the Container App Environment (module 10)
  exists.
- `snet-dev-pg` blocks while the PostgreSQL Flexible Server (module 09)
  exists.

Destroy those modules FIRST — the reverse of the dependency order in
[`docs/MODULES_DEPENDENCY.md`](../../../../docs/MODULES_DEPENDENCY.md).

Private DNS zones and PE-linked records may also block if a private endpoint
in a downstream module still references them; destroy those modules first.

No post-destroy purge needed.

## Reprovision

Same commands as **Provision** — `terraform init` is idempotent.

## Notes

- No `terraform.tfvars` values needed, and no file needed either. Nothing is
  passed unconditionally any more: `terraform.tfvars` is auto-loaded when
  present, and every value can come from a `TF_VAR_*` environment variable
  instead. See
  [INITIAL_SETUP](../../../INITIAL_SETUP.md#terraform-environment).
- Address plan (VNet CIDR + subnet CIDRs) is hard-coded in the child module
  (`modules/networking/main.tf`). Change there if you need to, not here.
- The set of private DNS zones is fixed — one per PE-integrated downstream
  service. Adding one is a breaking change that requires the downstream
  module to consume the new output.
