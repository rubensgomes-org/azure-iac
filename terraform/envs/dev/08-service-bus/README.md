# 08-service-bus (envs/dev)

Root Terraform config that provisions the shared Service Bus namespace for
the `dev` environment, any queues listed in `terraform.tfvars`, and the two
RBAC role assignments (`Azure Service Bus Data Sender` +
`Azure Service Bus Data Receiver`) granted to the shared UAMI. State lives
in `tfstate/service-bus/terraform.tfstate` on the bootstrap storage
account.

Wraps [`../../../modules/service-bus/`](../../../modules/service-bus/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads `rg_data_name`
  from its remote state.
- Module 04 (`04-managed-identities`) applied — this root reads
  `uami_app_principal_id` from its remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env`, `location`, `tags`.

## Provision

```bash
cd terraform/envs/dev/08-service-bus

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=service-bus/terraform.tfstate"

terraform plan \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Namespace exists with the expected posture
SB_NAME=$(terraform output -raw sb_namespace_name)
az servicebus namespace show -g rg-dev-data -n "$SB_NAME" \
  --query "{name:name, status:status, sku:sku.name, tls:minimumTlsVersion, localAuth:disableLocalAuth, publicNet:publicNetworkAccess}" \
  -o table
# Expect status=Active, sku=Standard, tls=1.2, localAuth=false
# (disableLocalAuth=false means local auth is ENABLED — inverse naming),
# publicNet=Enabled.

# Queues, if any (empty output means `queues = []`)
az servicebus queue list -g rg-dev-data --namespace-name "$SB_NAME" \
  --query "[].name" -o tsv

# RBAC assignments granted to the shared UAMI
UAMI_PRINCIPAL=$(cd ../04-managed-identities && terraform output -raw uami_app_principal_id)
az role assignment list \
  --scope "$(terraform output -raw sb_namespace_id)" \
  --assignee "$UAMI_PRINCIPAL" \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
# Expect two rows at the namespace scope:
#   - Azure Service Bus Data Sender
#   - Azure Service Bus Data Receiver
```

Read the outputs Terraform will hand to downstream modules:

```bash
terraform output sb_namespace_id
terraform output sb_namespace_fqdn
terraform output sb_queue_names
```

## Destroy

```bash
cd terraform/envs/dev/08-service-bus

terraform destroy \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars
```

No post-destroy purge needed — the namespace name is released immediately
(no soft-delete tombstone on Standard SKU).

**Order matters.** Container Apps (module 11) send/receive messages via
the shared UAMI. Destroy module 11 first — otherwise running apps will
see 401s the moment the RBAC assignments (or the namespace) disappear.

## Reprovision

Same commands as **Provision**. The `random_id` suffix is keyed on `env`,
so reprovisioning the same env lands on a fresh name
(`sb-dev-msg-<newhex>`).

See [`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md) §8
for the reprovision shortcut.

## Notes

- SKU (`Standard`), local-auth flag, TLS min, and public-network flag are
  hard-coded in the child module (`modules/service-bus/main.tf`). Change
  there if you need to move to Premium (dedicated capacity, PE, geo-DR)
  or flip local auth off.
- `local_auth_enabled = true` for now (§9 of the master plan). All *apps*
  use AAD via the shared UAMI regardless — local SAS is a debugging
  escape hatch. Flip to `false` in `modules/service-bus/main.tf` once
  every app is confirmed passwordless.
- Queues live in this root's `terraform.tfvars`, not the shared
  `env.tfvars`, because queue topology is a service-bus concern (many
  apps might share one queue, or one app might own several). Add queue
  names to `queues = [...]` in `terraform.tfvars` when the apps need
  them.
- No customer-managed key (encryption-at-rest uses the Microsoft-managed
  key). If we add CMK later, wire remote state from `05-key-vault`
  following the pattern in this root's `main.tf`.
- No private endpoint yet. Adding one requires wiring remote state from
  `02-networking` for `subnet_pe_id` and provisioning the
  `privatelink.servicebus.windows.net` zone (not yet created in module
  02). Small future change.
