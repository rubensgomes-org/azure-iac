# modules/web-iq

Child Terraform module that provisions a Microsoft Web IQ account.

Called by `terraform/roots/19-web-iq/`.

## Resources created

| Type             | Name                     | Notes                                                      |
|------------------|--------------------------|------------------------------------------------------------|
| `azapi_resource` | `wiq-<workload>ai-<env>` | `Microsoft.WebIQ/accounts`, `WebIQ.Grounding`, G3, global  |

## Inputs

| Name                | Type          | Required | Notes                                  |
|---------------------|---------------|----------|----------------------------------------|
| `workload`, `env`   | `string`      | `env`    | CAF name tokens.                       |
| `resource_group_id` | `string`      | yes      | ai RG (module 01).                     |
| `tags`              | `map(string)` | no       | Merged with `component = "web-iq"`.    |

## Outputs

- `web_iq_id`, `web_iq_name`

## Caveats

- **Access:** the subscription must be enabled for Web IQ by Microsoft and
  have the `Microsoft.WebIQ` provider registered.
- **No RBAC:** bind a caller's client ID to a Web IQ AppID in the Web IQ
  portal (https://webiq.microsoft.ai/profiles).
