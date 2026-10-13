# modules/app-gateway

Child Terraform module that publishes one Container App from the internal
Container App Environment through an Application Gateway v2.

Called by `terraform/roots/14-app-gateway/`.

## Resources created

| Type                            | Name                         | Notes                                       |
|---------------------------------|------------------------------|---------------------------------------------|
| `azurerm_network_security_rule` | on `nsg-<workload>agw-<env>` | GatewayManager 65200-65535; HTTP 80 inbound |
| `azurerm_public_ip`             | `pip-<workload>agw-<env>`    | Standard, static, DNS label                 |
| `azurerm_application_gateway`   | `agw-<workload>-<env>`       | Standard_v2, autoscale 0-2                  |

## Inputs

| Name                  | Type           | Required | Notes                                     |
|-----------------------|----------------|----------|-------------------------------------------|
| `workload`, `env`     | `string`       | `env`    | CAF name tokens.                          |
| `location`            | `string`       | yes      | Azure region.                             |
| `resource_group_name` | `string`       | yes      | Network RG (module 01).                   |
| `subnet_id`, `nsg_id` | `string`       | yes      | `agw` subnet and NSG (module 02).         |
| `dns_label`           | `string`       | yes      | `<label>.<location>.cloudapp.azure.com`.  |
| `public_source_cidrs` | `list(string)` | no       | Allowed clients. Default `0.0.0.0/0`.     |
| `backend_ip_address`  | `string`       | yes      | Environment static IP (module 11).        |
| `backend_host_name`   | `string`       | yes      | App FQDN (module 12).                     |
| `health_probe_path`   | `string`       | no       | Default `/health`.                        |
| `tags`                | `map(string)`  | no       | Merged with `component = "app-gateway"`.  |

## Outputs

- `agw_id`, `agw_name`
- `agw_public_ip_address`, `agw_public_fqdn`, `agw_public_url`

## Caveats

- **Cost:** the Standard_v2 fixed charge applies while the gateway exists.
- **HTTP only:** HTTPS needs a custom domain and certificate.
- **No scale to zero:** health probes keep one app replica running.

This project's source code and documentation were generated with the
assistance of Artificial Intelligence (AI). For more information, please
refer to the `AI_DISCLAIMER.md` document located in the project's root
directory.
