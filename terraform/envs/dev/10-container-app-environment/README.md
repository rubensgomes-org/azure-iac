# 10-container-app-environment (envs/dev)

Root Terraform config that provisions the shared Azure Container Apps
Environment (ACAE / CAE) for the `dev` environment. The environment
hosts every microservice Container App (module 11) and streams container
stdout/stderr to the shared Log Analytics Workspace (module 03). State
lives in `tfstate/container-app-environment/terraform.tfstate` on the
bootstrap storage account.

Wraps [`../../../modules/container-app-environment/`](../../../modules/container-app-environment/README.md).

## Prerequisites

- Modules **01** (`01-resource-groups`), **02** (`02-networking`), and
  **03** (`03-log-analytics`) applied. This root reads `rg_app_name`,
  `subnet_app_id`, and `law_id` from their remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`,
  `ARM_SUBSCRIPTION_ID` exported in the current shell.
- `../env.tfvars` populated with `env`, `location`, and `tags`.

## Provision

```bash
cd terraform/envs/dev/10-container-app-environment

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=container-app-environment/terraform.tfstate"

terraform plan \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars \
  -out=tfplan

terraform apply tfplan
```

Apply time is ~5-8 minutes on a fresh environment — Azure has to place
the compute plane on the delegated subnet and provision the ingress
static IP.

## Verify

```bash
# Environment exists, provisioning state = Succeeded
az containerapp env show -g rg-dev-app -n cae-dev \
  --query "{name:name, state:properties.provisioningState, defaultDomain:properties.defaultDomain, staticIp:properties.staticIp}" \
  -o table
# Expect state=Succeeded, defaultDomain=<random>.eastus.azurecontainerapps.io.

# VNet integration wired to snet-dev-app
az containerapp env show -g rg-dev-app -n cae-dev \
  --query "properties.vnetConfiguration.infrastructureSubnetId" -o tsv
# Expect: .../virtualNetworks/vnet-dev/subnets/snet-dev-app

# Log Analytics workspace wired
az containerapp env show -g rg-dev-app -n cae-dev \
  --query "properties.appLogsConfiguration.destination" -o tsv
# Expect: log-analytics
```

Sanity outputs from Terraform:

```bash
terraform output cae_default_domain   # <random>.eastus.azurecontainerapps.io
terraform output cae_static_ip_address # public IP for external ingress
```

## Destroy

```bash
cd terraform/envs/dev/10-container-app-environment

terraform destroy \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars
```

**Order matters.** Azure refuses to delete a CAE while any Container App
inside it still exists — always destroy module 11 first, then this one.
If a stuck app survives (e.g. one created manually outside Terraform),
delete it with `az containerapp delete -g rg-dev-app -n <app> --yes`
before retrying.

Post-destroy, the CAE name (`cae-dev`) is immediately free — Container
App Environments do not use a soft-delete window.

## Notes

- **Consumption-only workload profile.** The child module declares no
  `workload_profile` block; azurerm 4.x treats that as Consumption-only
  and bills per-request. Add explicit profile blocks in the child
  module if a workload later needs dedicated compute (`D4`, `E4`, ...).
- **External ingress** — the environment provisions a public static IP.
  Flip `internal_load_balancer_enabled` to `true` in the child module
  for private-only ingress (needs a VNet-reachable client).
- **No zone redundancy** — enabling it demands a subnet that spans all
  three AZs; module 02 provisions a single-AZ /23.
- **Log Analytics wiring** uses `log_analytics_workspace_id` (the ARM
  resource ID), not the legacy `customer_id` + `primary_shared_key`
  pair. Cleaner and passwordless.
- **Fixed name `cae-dev`** — no random suffix. Container App
  Environments have no soft-delete recycle bin, so destroy+recreate is
  free of the naming dance PG / KV / LAW go through.
