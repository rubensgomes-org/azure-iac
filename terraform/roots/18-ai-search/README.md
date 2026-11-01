# 18-ai-search (terraform/roots)

Root Terraform config that provisions an Azure AI Search service and the
storage account it indexes in the ai resource group. State lives at key
`ai-search/<region>/terraform.tfstate` in the backend blob container, one
per region.

Wraps [`../../modules/ai-search/`](../../modules/ai-search/README.md).

## Prerequisites

- Modules 01 (the ai RG) and 04 (the shared UAMI) applied.
- Same credentials and `TF_VAR_*` / `env.tfvars` setup as every other root.
- Region: `TF_VAR_foundry_location`, else `TF_VAR_location`.
- Optional `TF_VAR_search_user_object_id` for portal access.

## Provision

```bash
make apply-ai-search
```

## Verify

```bash
az search service show \
  -g rg-<workload>ai-<env>-<region> -n srch-<workload>ai-<env>-<region> \
  --query provisioningState -o tsv
```

## Destroy

```bash
make destroy-ai-search
```

Removes the search service and the storage account with every blob in it.
The RG stays in module 01.
