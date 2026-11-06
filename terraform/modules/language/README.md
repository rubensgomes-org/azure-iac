# modules/language

Child Terraform module that provisions an Azure AI Language resource.

Called by `terraform/roots/20-language/`.

## Resources created

| Type                        | Name                               | Notes                                        |
|-----------------------------|------------------------------------|----------------------------------------------|
| `azurerm_cognitive_account` | `lang-<workload>ai-<env>-<region>` | `TextAnalytics`, S, custom subdomain = name  |
| `azurerm_role_assignment`   | —                                  | UAMI "Cognitive Services User"               |

## RBAC

The shared UAMI used by the container apps (module 04) gets "Cognitive
Services User", assigned by role definition ID and scoped to the resource.
API keys are disabled (`local_auth_enabled = false`), so callers must use
Entra ID.

## Inputs

| Name                  | Type          | Required | Notes                                 |
|-----------------------|---------------|----------|---------------------------------------|
| `workload`, `env`     | `string`      | `env`    | CAF name tokens.                      |
| `location`            | `string`      | yes      | Azure region; resource name suffix.   |
| `resource_group_name` | `string`      | yes      | ai RG (module 01).                    |
| `uami_principal_id`   | `string`      | yes      | Shared UAMI (module 04).              |
| `tags`                | `map(string)` | no       | Merged with `component = "language"`. |

## Outputs

- `language_id`, `language_name`

## Caveats

- **Soft delete:** a deleted resource keeps its subdomain until purged. The
  root purges on destroy.
