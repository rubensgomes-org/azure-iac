# 15-foundry (terraform/roots)

Root Terraform config that provisions an Azure AI Foundry resource, one
project and a connected Application Insights in the ai resource group, and
grants the shared UAMI "Cognitive Services OpenAI User" on it. State lives at key
`foundry/terraform.tfstate` in the backend blob container.

Wraps [`../../modules/foundry/`](../../modules/foundry/README.md).

## Prerequisites

- Modules 01 (the ai RG), 03 (the workspace) and 04 (the shared UAMI)
  applied.
- Same credentials and `TF_VAR_*` / `env.tfvars` setup as every other root.

## Provision

```bash
export TF_VAR_foundry_user_object_id="<user-object-id>"   # optional
export TF_VAR_foundry_location="<region>"                 # optional
make apply-foundry
```

## Verify

```bash
az cognitiveservices account show \
  -g rg-<workload>ai-<env> -n aif-<workload>-<env> \
  --query properties.provisioningState -o tsv
az cognitiveservices account project show \
  -g rg-<workload>ai-<env> -n aif-<workload>-<env> \
  --project-name proj-<workload>-<env> \
  --query properties.provisioningState -o tsv
```

## Destroy

```bash
make destroy-foundry
```

Removes the project and the resource, with every model deployment on it,
then purges the soft-deleted resource. The RG stays in module 01.
