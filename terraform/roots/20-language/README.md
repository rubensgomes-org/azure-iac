# 20-language (terraform/roots)

Root Terraform config that provisions an Azure AI Language resource in the
ai resource group and grants the shared UAMI "Cognitive Services User" on
it. State lives at key `language/<region>/terraform.tfstate` in the backend
blob container, one per region.

Wraps [`../../modules/language/`](../../modules/language/README.md).

## Prerequisites

- Modules 01 (the ai RG) and 04 (the shared UAMI) applied.
- Same credentials and `TF_VAR_*` / `env.tfvars` setup as every other root.
- Region: `TF_VAR_foundry_location`, else `TF_VAR_location`.

## Provision

```bash
make apply-language
```

## Verify

```bash
az cognitiveservices account show \
  -g rg-<workload>ai-<env>-<region> -n lang-<workload>ai-<env>-<region> \
  --query properties.provisioningState -o tsv
```

## Destroy

```bash
make destroy-language
```

Removes the resource, then purges the soft-deleted resource. The RG stays
in module 01.
