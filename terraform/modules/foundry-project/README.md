# modules/foundry-project

Child Terraform module that provisions one project under an existing Azure
AI Foundry resource ([`../foundry-resource/`](../foundry-resource/README.md)).

Called by `terraform/roots/16-foundry-project/`.

## Resources created

| Type                                | Name                                            | Notes                    |
|-------------------------------------|-------------------------------------------------|--------------------------|
| `azurerm_cognitive_account_project` | `proj-<workload>ai<name_suffix>-<env>-<region>` | System-assigned identity |

## Inputs

| Name              | Type          | Required | Notes                                  |
|-------------------|---------------|----------|----------------------------------------|
| `workload`, `env` | `string`      | `env`    | CAF name tokens.                       |
| `name_suffix`     | `string`      | no       | 2-16 lowercase alnum. Default `""`.    |
| `location`        | `string`      | yes      | Region of the Foundry resource.        |
| `foundry_id`      | `string`      | yes      | Foundry resource (module 15).          |
| `tags`            | `map(string)` | no       | Merged with `component = "foundry"`.   |

## Outputs

- `foundry_project_id`, `foundry_project_name`
- `foundry_project_principal_id`

## Caveats

- **No RBAC:** grant the project identity roles it needs (e.g. AI Search)
  separately.
