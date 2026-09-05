# modules/postgresql/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# SKU (`B_Standard_B1ms`), engine version (`16`), storage (32 GB), backup
# retention (7 days), and other posture flags are HARD-CODED in main.tf as
# locals. Bumping the SKU tier, adding HA, or extending backup retention is
# a deliberate design change — not a per-environment knob.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into the server name
    (`psql-<env>-<random>`) and drives the random-suffix keeper.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the Flexible Server. Must match the location of the
    RG passed via `resource_group_name`.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the server. Caller supplies `rg-<env>-data`
    (from module 01's outputs). Data RG is the right home — PostgreSQL
    lifecycle is aligned with Service Bus and Storage (protected from
    `app` RG churn).
  EOT
  type        = string
}

variable "tenant_id" {
  description = <<-EOT
    Entra tenant ID. Set on the server's `authentication` block AND on the
    AAD administrator resource. Caller reads it from
    `data.azurerm_client_config.current.tenant_id` in the root — passing
    it in keeps the child module free of provider-config lookups.
  EOT
  type        = string
}

variable "pg_entra_admin_group_object_id" {
  description = <<-EOT
    Object ID of the Entra ID group whose members administer PostgreSQL.
    Bound to the server via
    `azurerm_postgresql_flexible_server_active_directory_administrator`.
    Members connect as PG admin using their own Entra token — the
    Terraform SP MUST be a member so the null_resource can call
    `pgaadauth_create_principal`.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.pg_entra_admin_group_object_id))
    error_message = "pg_entra_admin_group_object_id must be a valid GUID (36 chars, hyphens included)."
  }
}

variable "pg_entra_admin_group_name" {
  description = <<-EOT
    Display name of the Entra ID group referenced by
    `pg_entra_admin_group_object_id`. Used two ways:
      - as `principal_name` on the AAD administrator resource,
      - as the `PGUSER` value in the psql bootstrap (individual member
        connections use the group's display name as the login when the
        admin is a group).
    Caller looks this up in the root via `data.azuread_group`.
  EOT
  type        = string
}

variable "runner_public_ip" {
  description = <<-EOT
    Public IP address of the machine running `terraform apply`. Added as a
    single-IP firewall rule so the null_resource psql call can reach the
    server. Caller sources this via the `http` data source (e.g.
    `https://api.ipify.org`) — passing it in keeps this module free of
    provider dependencies used only for bootstrap connectivity.
  EOT
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.runner_public_ip))
    error_message = "runner_public_ip must be a dotted-quad IPv4 address."
  }
}

variable "apps" {
  description = <<-EOT
    Microservice names. One `azurerm_postgresql_flexible_server_database`
    is created per name AND one CONNECT + schema grant is issued per name
    to the shared UAMI. Empty list = server + admin only, no per-app DBs
    or grants.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.apps : can(regex("^[a-z][a-z0-9_]{0,62}$", a))])
    error_message = "Each app name must be 1-63 chars, lowercase alnum + underscore, starting with a letter (PostgreSQL identifier rules; used as the database name)."
  }
}

variable "uami_name" {
  description = <<-EOT
    Name of the shared UAMI (`id-<env>-app` from module 04). Used verbatim
    as the login name passed to `pgaadauth_create_principal` and as the
    grantee on every per-DB grant. Azure PG resolves this to the AAD
    principal by name — no object_id needed at this call.
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to the Flexible Server. Merged with a module-local
    `component` tag for cost / graph queries.
  EOT
  type        = map(string)
  default     = {}
}

variable "run_bootstrap" {
  description = <<-EOT
    Whether to run the in-line `null_resource.pg_bootstrap` psql step
    that registers the shared UAMI as an AAD principal and applies
    per-DB grants.

    Default `false` — the bootstrap has to run from a network that can
    reach the PG public endpoint on TCP 5432. Many corporate / home
    ISPs block outbound 5432 unconditionally, which turns Terraform
    apply into an unrecoverable failure. See
    `envs/dev/09-postgresql/README.md` → Troubleshooting for two
    workarounds:

      1. Run the bootstrap manually ONCE from Azure Cloud Shell (Cloud
         Shell egresses inside Azure and is covered by the
         `allow-azure-services` firewall rule). Keep this variable
         `false`; Terraform stays out of the data plane.

      2. Move the bootstrap to a Container Apps Job triggered by GitHub
         Actions after apply (see 09-postgresql/README.md for
         the follow-on design). Once that lands, this variable and the
         `null_resource` disappear entirely.

    Set to `true` only if you know your runner can reach the PG public
    endpoint on 5432 (e.g. a self-hosted runner inside an Azure VNet,
    or a home network that allows outbound 5432).
  EOT
  type        = bool
  default     = false
}
