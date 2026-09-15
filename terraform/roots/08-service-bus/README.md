# 08-service-bus (terraform/roots)

Root Terraform config that provisions the shared Service Bus namespace for
the target environment, any queues listed in `TF_VAR_queues`, and the two
RBAC role assignments (`Azure Service Bus Data Sender` + `Azure Service Bus
Data Receiver`) granted to the shared UAMI. State lives at key
`service-bus/terraform.tfstate` in the backend blob container.

Wraps [`../../modules/service-bus/`](../../modules/service-bus/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads `rg_data_name`
  from its remote state.
- Module 04 (`04-managed-identities`) applied — this root reads
  `uami_app_principal_id` from its remote state.
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
cd terraform/roots/08-service-bus

terraform init \
  -backend-config=../../envs/<env>/backend.hcl \
  -backend-config="key=service-bus/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

## Verify

```bash
# Namespace exists with the expected posture
SB_NAME=$(terraform output -raw sb_namespace_name)
az servicebus namespace show -g "rg-${TF_VAR_workload:-rgomes}data-${TF_VAR_env:-lab}" -n "$SB_NAME" \
  --query "{name:name, status:status, sku:sku.name, tls:minimumTlsVersion, localAuth:disableLocalAuth, publicNet:publicNetworkAccess}" \
  -o table
# Expect status=Active, sku=Standard, tls=1.2, localAuth=false
# (disableLocalAuth=false means local auth is ENABLED — inverse naming),
# publicNet=Enabled.

# Queues, if any (empty output means `queues = []`)
az servicebus queue list -g "rg-${TF_VAR_workload:-rgomes}data-${TF_VAR_env:-lab}" --namespace-name "$SB_NAME" \
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
cd terraform/roots/08-service-bus

terraform destroy
```

No post-destroy purge needed — the namespace name is released immediately
(no soft-delete tombstone on Standard SKU).

## Reprovision

Same commands as **Provision**. The name is the deterministic
`sb-<workload>msg-<env>`, so reprovisioning the same env lands on the SAME
name. Service Bus keeps no soft-delete tombstone on a namespace name, so that
name is free again the moment the destroy completes — nothing to purge.

## Notes

- SKU (`Standard`), local-auth flag, TLS min, and public-network flag are
  hard-coded in the child module (`modules/service-bus/main.tf`). Change
  there if you need to move to Premium (dedicated capacity, PE, geo-DR)
  or flip local auth off.
- `local_auth_enabled = true` for now. All *apps*
  use AAD via the shared UAMI regardless — local SAS is a debugging
  escape hatch. Flip to `false` in `modules/service-bus/main.tf` once
  every app is confirmed passwordless.
- Queues travel as `TF_VAR_queues`, not in the shared `env.tfvars`, because
  queue topology is a service-bus concern (many apps might share one queue,
  or one app might own several). Not a `terraform.tfvars` here either: this
  root is shared by every environment, so a file would give them all the same
  topology — `make check-tfvars` rejects one. Export
  `TF_VAR_queues='["orders","events"]'` when the apps need them.
- No customer-managed key (encryption-at-rest uses the Microsoft-managed
  key). If we add CMK later, wire remote state from `05-key-vault`
  following the pattern in this root's `main.tf`.
- No private endpoint yet. The `privatelink.servicebus.windows.net` zone
  is already provisioned by module 02 and linked to the VNet; adding a PE
  means wiring remote state from `02-networking` for `subnet_pe_id` and
  `dns_zone_sb_id`. Small future change.
