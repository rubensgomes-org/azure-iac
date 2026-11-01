# 17-document-intelligence (terraform/roots)

Root Terraform config that provisions an Azure AI Document Intelligence
resource in the ai resource group, and grants the shared UAMI "Cognitive
Services User" on it. State lives at key
`document-intelligence/terraform.tfstate` in the backend blob container.

Wraps
[`../../modules/document-intelligence/`](../../modules/document-intelligence/README.md).

## Prerequisites

- Modules 01 (the ai RG) and 04 (the shared UAMI) applied.
- Same credentials and `TF_VAR_*` / `env.tfvars` setup as every other root.

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

Removes the resource, then purges the soft-deleted resource. The RG stays in
module 01.
