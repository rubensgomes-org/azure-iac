# modules/ai-search

Child Terraform module that provisions an Azure AI Search service and the
storage account whose blobs it indexes.

Called by `terraform/roots/18-ai-search/`.

## Resources created

| Type                      | Name                               | Notes                                   |
|---------------------------|------------------------------------|-----------------------------------------|
| `azurerm_storage_account` | `st<workload>srch<env><region>`    | Blob, LRS, no shared keys; created first |
| `azapi_resource`          | `documents`                        | Private blob container                  |
| `azurerm_search_service`  | `srch-<workload>ai-<env>-<region>` | Basic, Entra ID only, system identity   |
| `azurerm_role_assignment` | —                                  | Search and blob grants                  |

## RBAC

API keys are disabled (`local_authentication_enabled = false`), so callers
must use Entra ID.

- The search system identity gets "Storage Blob Data Reader".
- The shared UAMI (module 04) gets "Search Index Data Reader" and "Storage
  Blob Data Contributor".
- The optional `search_user_object_id` gets "Search Service Contributor",
  "Search Index Data Contributor" and "Storage Blob Data Contributor".

## Inputs

| Name                    | Type          | Required | Notes                                  |
|-------------------------|---------------|----------|----------------------------------------|
| `workload`, `env`       | `string`      | `env`    | CAF name tokens.                       |
| `location`              | `string`      | yes      | Azure region; resource name suffix.    |
| `resource_group_name`   | `string`      | yes      | ai RG (module 01).                     |
| `uami_principal_id`     | `string`      | yes      | Shared UAMI (module 04).               |
| `search_user_object_id` | `string`      | no       | Portal user; null skips the grants.    |
| `tags`                  | `map(string)` | no       | Merged with `component = "ai-search"`. |

## Outputs

- `search_service_id`, `search_service_name`
- `storage_account_name`, `container_name`
