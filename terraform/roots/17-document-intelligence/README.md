# 17-document-intelligence (terraform/roots)

Root Terraform config that provisions an Azure AI Document Intelligence
resource in the ai resource group, grants the shared UAMI "Cognitive
Services User" on it, and creates its training storage account. State lives at key
`document-intelligence/<region>/terraform.tfstate` in the backend blob
container, one per region.

Wraps
[`../../modules/document-intelligence/`](../../modules/document-intelligence/README.md).

## Prerequisites

- Modules 01 (the ai RG) and 04 (the shared UAMI) applied.
- Same credentials and `TF_VAR_*` / `env.tfvars` setup as every other root.
- Region: `TF_VAR_foundry_location`, else `TF_VAR_location`.

## Provision

```bash
make apply-document-intelligence
```

## Verify

```bash
az cognitiveservices account show \
  -g rg-<workload>ai-<env>-<region> -n di-<workload>ai-<env>-<region> \
  --query properties.provisioningState -o tsv
```

## Destroy

```bash
make destroy-document-intelligence
```

Removes the resource and the training storage with every blob in it, then
purges the soft-deleted resource. The RG stays in
module 01.
