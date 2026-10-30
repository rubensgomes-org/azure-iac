# 15-foundry (terraform/roots)

Root Terraform config that provisions an Azure AI Foundry resource, one
project and an optional connected Application Insights in the ai resource
group, and grants the shared UAMI "Cognitive Services OpenAI User" on it.
State lives at key `foundry/<region>/terraform.tfstate` in the backend blob
container, one per region (`TF_VAR_foundry_location`, else `TF_VAR_location`).

Wraps [`../../modules/foundry/`](../../modules/foundry/README.md).

## Prerequisites

- Modules 01 (the ai RG), 03 (the workspace) and 04 (the shared UAMI)
  applied.
- Same credentials and `TF_VAR_*` / `env.tfvars` setup as every other root.

## Provision

```bash
export TF_VAR_foundry_user_object_id="<user-object-id>"   # optional
export TF_VAR_foundry_location="<region>"                 # optional
export TF_VAR_app_insights_enabled=false                  # optional
make apply-foundry
```

## Verify

```bash
az cognitiveservices account show \
  -g rg-<workload>ai-<env>-<region> -n aif-<workload>ai-<env>-<region> \
  --query properties.provisioningState -o tsv
az cognitiveservices account project show \
  -g rg-<workload>ai-<env>-<region> -n aif-<workload>ai-<env>-<region> \
  --project-name proj-<workload>ai-<env>-<region> \
  --query properties.provisioningState -o tsv
```

## Destroy

```bash
make destroy-foundry
```

Removes the project and the resource, with every model deployment on it,
then purges the soft-deleted resource. The RG stays in module 01.
