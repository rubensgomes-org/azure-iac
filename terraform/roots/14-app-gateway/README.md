# 14-app-gateway (terraform/roots)

Root Terraform config that publishes one Container App (default
`mathagent`) to the internet through an Application Gateway v2. State lives
at key `app-gateway/terraform.tfstate` in the backend blob container.

Wraps [`../../modules/app-gateway/`](../../modules/app-gateway/README.md).

## Prerequisites

- Modules 01, 02, 11 and 12 applied; module 02 includes the `agw` subnet.
- The app is in module 12's `ingress_external_apps`, e.g.
  `TF_VAR_ingress_external_apps='["mathagent"]'`.
- Same credentials and `TF_VAR_*` / `env.tfvars` setup as every other root.

## Provision

```bash
export TF_VAR_public_source_cidrs='["<your-ip>/32"]'   # optional
make apply-app-gateway
terraform -chdir=terraform/roots/14-app-gateway output -raw agw_public_url
```

## Verify

```bash
az network application-gateway show-backend-health \
  -g rg-<workload>network-<env>-<region> -n agw-<workload>-<env>-<region> \
  --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].health"
curl "$(terraform -chdir=terraform/roots/14-app-gateway output -raw agw_public_url)/health"
```

## Destroy

```bash
make destroy-app-gateway
```

Removes the gateway, public IP and NSG rules; the subnet stays in module 02.
Destroy this root before modules 02, 11 and 12. The public IP changes on
recreate; the DNS name does not.
