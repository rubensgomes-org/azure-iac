# 19-web-iq (terraform/roots)

Root Terraform config that provisions a Microsoft Web IQ account in the ai
resource group. The account is global, so state lives at the single key
`web-iq/terraform.tfstate` in the backend blob container.

Wraps [`../../modules/web-iq/`](../../modules/web-iq/README.md).

## Prerequisites

- Module 01 (the ai RG) applied.
- Same credentials and `TF_VAR_*` / `env.tfvars` setup as every other root.
- A paid subscription enabled for Web IQ by Microsoft.
- `az provider register --namespace Microsoft.WebIQ --wait`, once per
  subscription.

## Provision

```bash
make apply-web-iq
```

Then, in the Web IQ portal (https://webiq.microsoft.ai/profiles), connect
the resource ID and bind the client ID of each caller, such as the shared
UAMI, to its AppID.

## Verify

```bash
az resource show \
  -g rg-<workload>ai-<env>-<region> -n wiq-<workload>ai-<env> \
  --resource-type Microsoft.WebIQ/accounts \
  --api-version 2026-06-01-preview --query id -o tsv
```

## Destroy

```bash
make destroy-web-iq
```

Removes the Web IQ account. The RG stays in module 01.
