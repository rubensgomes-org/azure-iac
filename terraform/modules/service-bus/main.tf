# modules/service-bus/main.tf
# -----------------------------------------------------------------------------
# Provisions one shared Service Bus namespace per env plus:
#   - the two RBAC grants that let the shared UAMI send and receive messages,
#   - one queue per name in `var.queues` (empty by default).
#
# No current consumer wires this module's outputs in — the shared UAMI
# already holds both RBAC grants, so a future consumer only needs
# `sb_namespace_fqdn` via `data.terraform_remote_state`.
#
# The passwordless model routes ALL app traffic through Entra tokens. Local
# SAS auth (`local_auth_enabled = true`) stays available at the namespace for
# now — see the local block below for the rationale and the flip point.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# SKU + posture (locals)
# -----------------------------------------------------------------------------
# - `Standard`: cheapest tier that supports topics/subscriptions in addition
#   to queues, plus the higher message-size and TTL limits worth having for
#   a playground. `Basic` would work for queues alone but boxes us in.
#   `Premium` (dedicated capacity, private endpoints, geo-DR) is overkill
#   and 100× the cost.
# - `local_auth_enabled = true`: leaves the classic SAS keys reachable at
#   the namespace. Flip it to `false` once every app is confirmed to
#   authenticate via AAD — until
#   then, keeping it on avoids a chicken-and-egg during first-run debugging
#   from `az servicebus ...` or a local dev machine.
# - `public_network_access_enabled = true`: matches the playground posture
#   (same as Storage, KV, ACR). Move to `false` + a PE against
#   `privatelink.servicebus.windows.net` (add the zone in module 02) later
#   if we want network isolation.
# - `minimum_tls_version = "1.2"`: rejects TLS 1.0/1.1 clients — no legacy
#   SDK is being deployed here anyway.
locals {
  sku                           = "Standard"
  local_auth_enabled            = true
  public_network_access_enabled = true
  minimum_tls_version           = "1.2"
  purpose                       = "msg"
}

# -----------------------------------------------------------------------------
# Service Bus namespace
# -----------------------------------------------------------------------------
# Name pattern: the CAF form sb-<workload>-<env> with the `msg` purpose folded
# onto the workload token, as everywhere else in the estate — "sb-rgomesmsg-lab".
# With `workload` ≤16, `env` ≤10, "sb-", "msg" and one dash, the worst case is
# 34 chars against a 50-char ceiling, so no precondition is needed here.
#
# No random suffix: names are deterministic estate-wide. Namespace names are
# globally unique across every Azure tenant (they resolve as
# `<name>.servicebus.windows.net`), so this can collide with a stranger's
# namespace — the trade the estate accepts for derivable names. There is no
# soft-delete tombstone on the namespace name, so unlike Key Vault and Log
# Analytics a destroyed name is reusable immediately.
resource "azurerm_servicebus_namespace" "this" {
  name                = "sb-${var.workload}${local.purpose}-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku                           = local.sku
  local_auth_enabled            = local.local_auth_enabled
  public_network_access_enabled = local.public_network_access_enabled
  minimum_tls_version           = local.minimum_tls_version

  tags = merge(
    var.tags,
    { component = "service-bus" },
  )
}

# -----------------------------------------------------------------------------
# RBAC — Data Sender + Data Receiver for the shared UAMI
# -----------------------------------------------------------------------------
# Two role assignments at the NAMESPACE scope — every queue (and future
# topic/subscription) inherits. Tightening to per-queue scope is a future
# move if we want per-app isolation; a future consumer would only need
# the queue names, not the role assignments themselves.
#
# `principal_type = "ServicePrincipal"` avoids a slow Entra lookup on every
# plan — UAMIs surface as service principals. Skipping this makes Terraform
# infer the type, which occasionally fails on brand-new identities (Entra
# hasn't propagated yet).
resource "azurerm_role_assignment" "uami_sb_sender" {
  scope                = azurerm_servicebus_namespace.this.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = var.uami_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "uami_sb_receiver" {
  scope                = azurerm_servicebus_namespace.this.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = var.uami_principal_id
  principal_type       = "ServicePrincipal"
}

# -----------------------------------------------------------------------------
# Queues (optional — one per entry in var.queues)
# -----------------------------------------------------------------------------
# All queue settings intentionally left at Azure defaults for the
# playground:
#   - `max_size_in_megabytes = 1024` (1 GiB, the Standard-SKU default)
#   - `default_message_ttl` = 14 days (default)
#   - `lock_duration` = 60s (default), `max_delivery_count` = 10 (default)
#   - `dead_lettering_on_message_expiration = false` (default)
# Tune per queue later if a specific workload needs it. Overriding here
# without a workload reason would be premature.
resource "azurerm_servicebus_queue" "this" {
  for_each = toset(var.queues)

  name         = each.key
  namespace_id = azurerm_servicebus_namespace.this.id
}
