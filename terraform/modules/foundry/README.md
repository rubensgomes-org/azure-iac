# modules/foundry

Child Terraform module that provisions an Azure AI Foundry resource and an
optional Application Insights connected for agent tracing. Projects live in
[`../foundry-project/`](../foundry-project/README.md).

Called by `terraform/roots/15-foundry/`.

## Resources created

| Type                                           | Name                             | Notes                                      |
|------------------------------------------------|----------------------------------|--------------------------------------------|
| `azurerm_cognitive_account`                    | `aif-<workload>ai-<env>-<region>`   | `AIServices`, S0, custom subdomain = name  |
| `azurerm_role_assignment`                      | —                                | UAMI "Cognitive Services OpenAI User"      |
| `azurerm_role_assignment`                      | —                                | "Foundry User"; only when a user ID is set |
| `azurerm_application_insights`                 | `appi-<workload>ai-<env>-<region>`        | Only when `app_insights_enabled`           |
| `azurerm_cognitive_account_connection_api_key` | `appi-<workload>ai-<env>-<region>`        | Only when `app_insights_enabled`           |

## RBAC

Both roles are assigned by role definition ID, scoped to the Foundry
resource.

| Principal                                    | Role                               |
|----------------------------------------------|------------------------------------|
| Shared UAMI used by the container apps (04)  | Cognitive Services OpenAI User     |
| `foundry_user_object_id` (optional)          | Foundry User                       |

The UAMI gets "Cognitive Services OpenAI User" rather than "Foundry User":
it covers model inference (including the Responses API) without granting
every `Microsoft.CognitiveServices/*` data action.

## Inputs

| Name                         | Type          | Required | Notes                                    |
|------------------------------|---------------|----------|------------------------------------------|
| `workload`, `env`            | `string`      | `env`    | CAF name tokens.                         |
| `location`                   | `string`      | yes      | Azure region; resource name suffix.      |
| `resource_group_name`        | `string`      | yes      | ai RG (module 01).                       |
| `log_analytics_workspace_id` | `string`      | yes      | Workspace (module 03).                   |
| `uami_principal_id`          | `string`      | yes      | Shared UAMI (module 04).                 |
| `app_insights_enabled`       | `bool`        | no       | Default `true`.                          |
| `foundry_user_object_id`     | `string`      | no       | User granted "Foundry User". Null skips. |
| `tags`                       | `map(string)` | no       | Merged with `component = "foundry"`.     |

## Outputs

- `foundry_id`, `foundry_name`
- `app_insights_id`, `app_insights_name` (null when disabled)

## Caveats

- **Soft delete:** a deleted resource keeps its subdomain until purged. The
  root purges on destroy.
- **Model deployments** and **projects** are managed outside this module
  and are deleted with the resource.
