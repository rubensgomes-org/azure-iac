# modules/postgresql

Child Terraform module that provisions the shared PostgreSQL Flexible
Server per environment, one database per microservice, an AAD-only
authentication posture with the Entra admin group as the PG
administrator, and the psql-driven data-plane bootstrap that registers
the shared UAMI as an AAD-authenticated PG role and grants it per-DB
privileges.

Called by `terraform/envs/dev/09-postgresql/`. State is owned by the
caller — this module has no `backend` block.

## Resources created

| Type                                                                | Name                  | Notes                                                                                                                                                              |
|---------------------------------------------------------------------|-----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `random_id`                                                         | `suffix`              | 4-hex-char suffix; keyed on `env`.                                                                                                                                 |
| `azurerm_postgresql_flexible_server`                                | `psql-<env>-<random>` | Burstable `B_Standard_B1ms`, PG 16, 32 GiB P4, 7-day backup, no HA/geo, AAD-only auth (`password_auth_enabled = false`).                                           |
| `azurerm_postgresql_flexible_server_active_directory_administrator` | `admin`               | Binds the Entra group as PG admin (`principal_type = "Group"`).                                                                                                    |
| `azurerm_postgresql_flexible_server_firewall_rule`                  | `runner`              | Single-IP allowlist for the Terraform runner.                                                                                                                      |
| `azurerm_postgresql_flexible_server_firewall_rule`                  | `azure_services`      | `0.0.0.0/0.0.0.0` magic pair — allow all Azure services.                                                                                                           |
| `azurerm_postgresql_flexible_server_database`                       | one per `var.apps`    | `en_US.utf8` / `UTF8`.                                                                                                                                             |
| `null_resource`                                                     | `pg_bootstrap`        | Runs `scripts/pg-bootstrap.sh.tftpl` via `local-exec` — registers the shared UAMI as an AAD principal and grants CONNECT + `USAGE, CREATE` on `public` per app DB. |

## Inputs

| Name                             | Type           | Required | Notes                                                                                       |
|----------------------------------|----------------|----------|---------------------------------------------------------------------------------------------|
| `env`                            | `string`       | yes      | Baked into name and random keeper. `^[a-z][a-z0-9]{1,9}$`.                                  |
| `location`                       | `string`       | yes      | Azure region. Must match the RG's location.                                                 |
| `resource_group_name`            | `string`       | yes      | Caller passes `rg-<env>-data` (from module 01).                                             |
| `tenant_id`                      | `string`       | yes      | Entra tenant ID. From `data.azurerm_client_config.current` in the root.                     |
| `pg_entra_admin_group_object_id` | `string`       | yes      | Object ID of the Entra group set as PG administrator.                                       |
| `pg_entra_admin_group_name`      | `string`       | yes      | Display name of that group. Used as `principal_name` on the admin resource and as `PGUSER`. |
| `runner_public_ip`               | `string`       | yes      | IPv4 of the machine running `terraform apply`. From `data.http.myip` in the root.           |
| `apps`                           | `list(string)` | no       | Microservice names. One DB + grants per name. Default `[]`.                                 |
| `uami_name`                      | `string`       | yes      | Name of the shared UAMI. Registered as the AAD-authenticated PG role.                       |
| `tags`                           | `map(string)`  | no       | Merged with `component = "postgresql"`.                                                     |

## Outputs

- `pg_server_id` — full Azure Resource ID
- `pg_server_name` — server name (`psql-<env>-<random>`)
- `pg_fqdn` — `<name>.postgres.database.azure.com`
- `pg_version` — engine major version
- `pg_location`
- `pg_databases` — map `{ <app> => <db_name> }`
- `pg_database_ids` — map `{ <app> => <full-resource-id> }`
- `pg_admin_group_object_id`, `pg_admin_login` — echoes of the admin binding

## Runner prerequisites (data-plane step)

`null_resource.pg_bootstrap` shells out to `bash`, `az`, and `psql` on
the Terraform runner. All three must be installed and on `PATH`. In
addition:

- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID` must be exported
  (the script does a scoped `az login --service-principal` inside a
  temporary `AZURE_CONFIG_DIR` so the runner's `~/.azure` is NOT
  mutated).
- The Terraform SP MUST be a member of the Entra group referenced by
  `pg_entra_admin_group_object_id`. Without membership the AAD token is
  issued but PG rejects the connection.
- The runner's public IP must be routable to Azure (the firewall rule
  is pinned to `runner_public_ip`).

## Design decisions

- **Burstable `B_Standard_B1ms`.** 1 vCPU + 2 GiB RAM, cheapest tier
  Flexible Server offers. General-Purpose starts at ~5× the cost.
- **PG 16.** Current Azure default; widest-supported major.
- **32 GiB / P4 storage.** Smallest supported size.
- **AAD-only auth (`password_auth_enabled = false`).** No SQL admin
  login exists — nothing to leak or rotate. §12 of the master plan.
- **Group as PG administrator, not a user or SP.** Membership can
  rotate in Entra without touching Terraform.
- **Public bootstrap posture.** `public_network_access_enabled = true`
    + two firewall rules (runner /32 + Azure Services). Move to VNet-only
      via `delegated_subnet_id = snet-pg` when the estate stabilises
      (§12 item 5). The delegated subnet already exists in module 02.
- **`null_resource` + `psql` for the AAD principal, not
  `cyrilgdn/postgresql`.** Master plan §12 recommends Option A
  (cyrilgdn), but `postgresql_role` runs `CREATE ROLE`, which in
  Azure Flexible Server with AAD-only auth produces a role that
  cannot log in. Only `pgaadauth_create_principal` produces
  AAD-authenticated roles, and no cyrilgdn resource wraps that
  stored procedure. Option B is the pragmatic choice here — the
  script is idempotent, and `triggers` keep re-runs to actual
  changes.
- **Grants scoped to schema `public`.** Enough for migrations
  (Flyway / Liquibase / etc.) to create tables. Apps that need custom
  schemas can create them at runtime — `CREATE` on `public` is
  sufficient for `CREATE SCHEMA`.
- **`ignore_changes = [zone]`.** Azure sometimes rewrites the zone in
  state after a stop/start cycle. Ignoring avoids spurious replace
  plans.

## Skipped dependencies (vs. the plan)

Master plan §4 lists modules 02 (network) and 05 (Key Vault) as
postgresql dependencies. Neither has a structural dep in the current
design:

- **02 network:** Public bootstrap posture — `delegated_subnet_id`
  and DNS integration are unused. When we flip to VNet-only, wire
  remote state to module 02 for `subnet_pg_id` and `dns_zone_pg_id`.
- **05 Key Vault:** No customer-managed key for encryption-at-rest,
  and no SQL admin password to stash (it doesn't exist). If we add
  CMK later, wire remote state to module 05.

## Downstream consumers

- **Container Apps (module 11):** each `azurerm_container_app` gets env
  vars `POSTGRES_HOST = <pg_fqdn>`, `POSTGRES_DB = pg_databases[<app>]`,
  `POSTGRES_USER = <uami_name>`. Apps authenticate via
  `DefaultAzureCredential` — no passwords, no connection strings.
