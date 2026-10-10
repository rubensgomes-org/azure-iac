# modules/app-configuration

Child Terraform module that provisions one Azure App Configuration store per
environment plus the RBAC role assignment that lets the shared UAMI read
key-values.

Called by `terraform/roots/05-app-configuration/`. State is owned by the
caller — this module has no `backend` block.

## Resources created

| Type | Name | Notes |
|------|------|-------|
| `azurerm_app_configuration` | `appcs-<workload>-<env>` | SKU `free`, local auth off, public network, system-assigned identity. |
| `azurerm_role_assignment` | Data Reader for UAMI | Role `App Configuration Data Reader` at store scope. |

## Inputs

| Name | Type | Required | Notes |
|------|------|----------|-------|
| `workload` | `string` | no | CAF workload token. Default `rgomes`. |
| `env` | `string` | yes | `^[a-z][a-z0-9]{1,9}$`. |
| `location` | `string` | yes | Azure region. Must match the RG's location. |
| `resource_group_name` | `string` | yes | Platform RG (from module 01). |
| `uami_principal_id` | `string` | yes | `principal_id` of the shared UAMI (from module 04). |
| `tags` | `map(string)` | no | Merged with `component = "app-configuration"`. |

## Outputs

- `appcs_id`, `appcs_name`, `appcs_location`
- `appcs_endpoint` — `https://<name>.azconfig.io`
- `appcs_principal_id` — store identity, granted Key Vault access by module 06
- `appcs_role_assignment_id`

## Caveats

- **`free` SKU:** one free store per subscription; no soft delete, replicas
  or private endpoints.
- **Key Vault references** in key-values are resolved by the client (the
  shared UAMI), not by the store.

This project's source code and documentation were generated with the
assistance of Artificial Intelligence (AI). For more information, please
refer to the `AI_DISCLAIMER.md` document located in the project's root
directory.
