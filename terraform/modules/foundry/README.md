# modules/foundry

Child Terraform module that provisions an Azure AI Foundry resource, one
project under it, and an Application Insights connected for agent tracing.

Called by `terraform/roots/15-foundry/`.

## Resources created

| Type                                           | Name                      | Notes                                      |
|------------------------------------------------|---------------------------|--------------------------------------------|
| `azurerm_cognitive_account`                    | `aif-<workload>-<env>`    | `AIServices`, S0, custom subdomain = name  |
| `azurerm_cognitive_account_project`            | `proj-<workload>-<env>`   | System-assigned identity                   |
| `azurerm_role_assignment`                      | —                         | UAMI "Cognitive Services OpenAI User"      |
| `azurerm_role_assignment`                      | —                         | "Foundry User"; only when a user ID is set |
| `azurerm_application_insights`                 | `appi-<workload>ai-<env>` | Workspace-based (module 03)                |
| `azurerm_cognitive_account_connection_api_key` | `appi-<workload>ai-<env>` | `AppInsights` connection for tracing       |

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
| `location`                   | `string`      | yes      | Azure region.                            |
| `resource_group_name`        | `string`      | yes      | ai RG (module 01).                       |
| `log_analytics_workspace_id` | `string`      | yes      | Workspace (module 03).                   |
| `uami_principal_id`          | `string`      | yes      | Shared UAMI (module 04).                 |
| `foundry_user_object_id`     | `string`      | no       | User granted "Foundry User". Null skips. |
| `tags`                       | `map(string)` | no       | Merged with `component = "foundry"`.     |

## Outputs

- `foundry_id`, `foundry_name`
- `foundry_project_id`, `foundry_project_name`
- `app_insights_id`, `app_insights_name`

## Caveats

- **Soft delete:** a deleted resource keeps its subdomain until purged. The
  root purges on destroy.
- **Model deployments** are managed outside this module and are deleted
  with the resource.
