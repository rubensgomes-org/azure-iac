# modules/postgresql/main.tf
# -----------------------------------------------------------------------------
# Provisions the shared PostgreSQL Flexible Server for the env plus:
#   - AAD-only auth with the Entra admin group as the PG administrator,
#   - one database per app in `var.apps`,
#   - two firewall rules (runner IP + Azure Services) so the Terraform SP
#     and future Container Apps can reach the server during the public
#     bootstrap phase,
#   - a null_resource that runs `psql` to register the shared UAMI as an
#     AAD-authenticated PG role and grants it CONNECT + schema privileges
#     on each app DB.
#
# Design notes tied to docs/PROVISIONING_PLAN.md:
#   - §9  — dev safety toggles: burstable B1ms, 7-day backup, no HA/geo,
#           `password_auth_enabled = false`.
#   - §12 — passwordless auth: the shared UAMI is the ONLY app-side
#           principal; per-app users are omitted deliberately.
#   - §12 item 5 — network posture: PUBLIC bootstrap (this file), plan to
#           flip to VNet-only via `delegated_subnet_id = snet-pg` in a
#           later iteration once the estate is stable.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Server posture (locals)
# -----------------------------------------------------------------------------
#   - `sku_name = "B_Standard_B1ms"`: cheapest Burstable tier. 1 vCPU +
#     2 GiB RAM. General-Purpose tiers start ~5× the cost.
#   - `version = "16"`: current Azure PG default and widest-supported
#     major. 17 is available but adds nothing this workload needs.
#   - `storage_mb = 32768`: 32 GiB, the smallest supported size.
#   - `storage_tier = "P4"`: matches 32 GiB. Azure snaps tier to size
#     — over-specifying is silently rejected on some size/tier pairs.
#   - `backup_retention_days = 7`: minimum. Higher retention costs more.
#   - `geo_redundant_backup_enabled = false`: single-region playground.
#   - `zone = "1"`: pin to zone 1 so re-applies don't propose a zone move
#     if Azure's default drifts.
#   - `public_network_access_enabled = true`: bootstrap posture (§12).
#     Firewall rules below narrow the actual reachability.
#   - `password_auth_enabled = false` + `active_directory_auth_enabled =
#     true`: no SQL admin login exists. Every connection uses an AAD
#     token.
locals {
  sku_name                      = "B_Standard_B1ms"
  version                       = "16"
  storage_mb                    = 32768
  storage_tier                  = "P4"
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  zone                          = "1"
  public_network_access_enabled = true
}

# -----------------------------------------------------------------------------
# Random suffix (global uniqueness + soft-delete-safe re-provision)
# -----------------------------------------------------------------------------
# Flexible Server names must be globally unique across every Azure tenant
# (they resolve as `<name>.postgres.database.azure.com`), 3-63 chars,
# lowercase alnum + hyphens. Azure keeps a soft-delete tombstone on the
# name for up to 7 days after drop; a random suffix keyed on `env`
# sidesteps the reprovision block.
resource "random_id" "suffix" {
  byte_length = 2 # 4 lowercase hex chars

  keepers = {
    env = var.env
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL Flexible Server (Entra-only auth)
# -----------------------------------------------------------------------------
# Name pattern: psql-<env>-<random> (e.g. "psql-dev-a7f2").
#
# `administrator_login` / `administrator_password` are OMITTED intentionally.
# With `password_auth_enabled = false`, azurerm 4.x accepts the create call
# without them — no SQL admin ever exists on this server, so there is
# nothing to leak or rotate.
resource "azurerm_postgresql_flexible_server" "this" {
  name                = "psql-${var.env}-${random_id.suffix.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name

  version                       = local.version
  sku_name                      = local.sku_name
  storage_mb                    = local.storage_mb
  storage_tier                  = local.storage_tier
  backup_retention_days         = local.backup_retention_days
  geo_redundant_backup_enabled  = local.geo_redundant_backup_enabled
  zone                          = local.zone
  public_network_access_enabled = local.public_network_access_enabled

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = var.tenant_id
  }

  tags = merge(
    var.tags,
    { component = "postgresql" },
  )

  # `zone` drift on re-apply: Azure occasionally rewrites the zone in the
  # state to null when the server is stopped/started. Ignoring the field
  # avoids a spurious "replace-in-place" plan.
  lifecycle {
    ignore_changes = [zone]
  }
}

# -----------------------------------------------------------------------------
# AAD administrator — Entra group binding
# -----------------------------------------------------------------------------
# Every AAD-authenticated Flex Server needs at least one administrator.
# Binding a GROUP (not an individual user or SP) means membership can
# rotate without touching Terraform: add/remove humans from the group in
# Entra, and their PG admin access follows.
#
# `principal_type = "Group"` is what makes members log in with the group's
# display name as the PGUSER — the token proves membership, PG accepts.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "admin" {
  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = var.resource_group_name

  tenant_id      = var.tenant_id
  object_id      = var.pg_entra_admin_group_object_id
  principal_name = var.pg_entra_admin_group_name
  principal_type = "Group"
}

# -----------------------------------------------------------------------------
# Firewall rules (public bootstrap posture)
# -----------------------------------------------------------------------------
# Two rules, both narrow the effective reachability of the server even
# though `public_network_access_enabled = true`:
#
#   1. `runner` — a /32 for the machine running Terraform. Needed for
#      the null_resource psql call. Sourced by the root via the `http`
#      data source; changes on every apply from a new location, which
#      is a known cost of the bootstrap posture.
#
#   2. `azure_services` — the magic pair 0.0.0.0/0.0.0.0. On Flexible
#      Server, this signals "allow all Azure services" (same convention
#      as classic Single Server). Needed so future Container Apps can
#      reach PG from within Azure without pinning their variable
#      outbound IPs. Move to VNet-only + delegated_subnet_id and drop
#      this rule when the estate leaves the public-bootstrap phase.
resource "azurerm_postgresql_flexible_server_firewall_rule" "runner" {
  name             = "allow-terraform-runner"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = var.runner_public_ip
  end_ip_address   = var.runner_public_ip
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# -----------------------------------------------------------------------------
# Per-app databases
# -----------------------------------------------------------------------------
# One database per entry in `var.apps`. Database name = app name; downstream
# module 11 injects `POSTGRES_DB = <app>` per Container App.
#
# `collation = "en_US.utf8"` + `charset = "UTF8"` are the Azure PG defaults;
# spelling them out makes drift explicit if a future Azure change flips
# the default.
resource "azurerm_postgresql_flexible_server_database" "app" {
  for_each = toset(var.apps)

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# -----------------------------------------------------------------------------
# Data-plane bootstrap — register shared UAMI + grant per-DB privileges
# -----------------------------------------------------------------------------
# Runs the psql script rendered from `scripts/pg-bootstrap.sh.tftpl`.
# See that file's header comment for the full rationale.
#
# Gated behind `var.run_bootstrap` (default `false`). Reason: the psql
# call needs outbound TCP 5432 from the runner to the PG public endpoint,
# and many corporate / home networks block that port unconditionally —
# every terraform apply becomes an unrecoverable failure. When gated off
# the SAME work is done manually ONCE from Azure Cloud Shell (see
# `envs/dev/09-postgresql/README.md`), and later replaced by a Container
# Apps Job (see `docs/PROVISIONING_PLAN.md` §12a).
#
# `depends_on` is exhaustive so the psql call cannot race any prerequisite:
#   - server + admin binding must exist before AAD auth works,
#   - firewall rule for the runner must exist before the psql TCP connect,
#   - every app DB must exist before its per-DB grants run.
#
# `triggers` re-run the script only when a stable value that affects the
# SQL changes. Re-apply with no changes → no psql call. The script itself
# is idempotent, so re-running when a trigger DOES fire is safe.
resource "null_resource" "pg_bootstrap" {
  count = var.run_bootstrap ? 1 : 0

  depends_on = [
    azurerm_postgresql_flexible_server_active_directory_administrator.admin,
    azurerm_postgresql_flexible_server_firewall_rule.runner,
    azurerm_postgresql_flexible_server_firewall_rule.azure_services,
    azurerm_postgresql_flexible_server_database.app,
  ]

  triggers = {
    server_id   = azurerm_postgresql_flexible_server.this.id
    uami_name   = var.uami_name
    admin_login = var.pg_entra_admin_group_name
    apps        = jsonencode(sort(var.apps))
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = templatefile("${path.module}/scripts/pg-bootstrap.sh.tftpl", {
      fqdn        = azurerm_postgresql_flexible_server.this.fqdn
      admin_login = var.pg_entra_admin_group_name
      uami_name   = var.uami_name
      apps        = var.apps
    })
  }
}
