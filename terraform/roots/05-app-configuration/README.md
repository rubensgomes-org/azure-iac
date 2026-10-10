# 05-app-configuration (terraform/roots)

Root Terraform config that provisions the shared App Configuration store for
the target environment plus the `App Configuration Data Reader` role
assignment granted to the shared UAMI. State lives at key
`app-configuration/terraform.tfstate` in the backend blob container.

Wraps [`../../modules/app-configuration/`](../../modules/app-configuration/README.md).

## Prerequisites

- Module 01 (`01-resource-groups`) applied — this root reads
  `rg_platform_name`.
- Module 04 (`04-managed-identities`) applied — this root reads
  `uami_app_principal_id`.
- `Microsoft.AppConfiguration` provider registered — see
  [`INITIAL_SETUP.md`](../../../docs/INITIAL_SETUP.md).
- Same credentials and `TF_VAR_*` / `env.tfvars` setup as every other root.

## Provision

```bash
make apply-app-configuration
```

## Verify

```bash
az appconfig show -n "$(terraform output -raw appcs_name)" \
  --query "{sku:sku.name, localAuth:disableLocalAuth, identity:identity.type}" \
  -o table
# Expect sku = free, localAuth = True (disabled), identity = SystemAssigned.
```

## Destroy

```bash
make destroy-app-configuration
```

Destroy modules 06 and 12 first; both read this root's state. The `free` SKU
has no soft delete, so the name is reusable immediately.

This project's source code and documentation were generated with the
assistance of Artificial Intelligence (AI). For more information, please
refer to the `AI_DISCLAIMER.md` document located in the project's root
directory.
