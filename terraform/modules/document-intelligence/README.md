# modules/document-intelligence

Child Terraform module that provisions an Azure AI Document Intelligence
resource and a storage account for custom model training data.

Called by `terraform/roots/17-document-intelligence/`.

## Resources created

| Type                        | Name                             | Notes                                          |
|-----------------------------|----------------------------------|------------------------------------------------|
| `azurerm_cognitive_account` | `di-<workload>ai-<env>-<region>` | `FormRecognizer`, S0, custom subdomain = name  |
| `azurerm_role_assignment`   | —                                | UAMI "Cognitive Services User"                 |
| `azurerm_storage_account`   | `st<workload>di<env><region>`    | No shared keys; CORS for Studio                |
| `azapi_resource`            | `training`                       | Private blob container                         |
| `azurerm_role_assignment`   | —                                | Blob grants on the storage account             |

## RBAC

The shared UAMI used by the container apps (module 04) gets "Cognitive
Services User", assigned by role definition ID and scoped to the resource.
API keys are disabled (`local_auth_enabled = false`), so callers must use
Entra ID.

On the training storage, the resource's system identity gets "Storage Blob
Data Reader". The UAMI and the optional `di_user_object_id` get "Storage
Blob Data Contributor".

## Inputs

| Name                  | Type          | Required | Notes                                              |
|-----------------------|---------------|----------|----------------------------------------------------|
| `workload`, `env`     | `string`      | `env`    | CAF name tokens.                                   |
| `location`            | `string`      | yes      | Azure region; resource name suffix.                |
| `resource_group_name` | `string`      | yes      | ai RG (module 01).                                 |
| `uami_principal_id`   | `string`      | yes      | Shared UAMI (module 04).                           |
| `di_user_object_id`   | `string`      | no       | Studio labeling user; null skips the grant.        |
| `tags`                | `map(string)` | no       | Merged with `component = "document-intelligence"`. |

## Outputs

- `document_intelligence_id`, `document_intelligence_name`
- `training_storage_account_name`, `training_container_name`

## Caveats

- **Soft delete:** a deleted resource keeps its subdomain until purged. The
  root purges on destroy.
