# modules/service-bus/main.tf
# -----------------------------------------------------------------------------
# Provisions one shared Service Bus namespace per env plus:
#   - the two RBAC grants that let the shared UAMI send and receive messages,
#   - one queue per name in `var.queues` (empty by default).
#
# Consumers:
#   - Container Apps (module 11) — apps send/receive via
#     `DefaultAzureCredential`, using the same shared UAMI that pulls the
#     image and reads from PG/Blob. No SAS keys, no connection strings.
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
#   the namespace. §9 of docs/PROVISIONING_PLAN.md calls out flipping this
#   to `false` once every app is confirmed to authenticate via AAD — until
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
# Random suffix (global uniqueness)
# -----------------------------------------------------------------------------
# Service Bus namespace names must be globally unique across every Azure
# tenant (they resolve as `<name>.servicebus.windows.net`), 6-50 chars,
# lowercase alnum + hyphens, starting with a letter and ending with a letter
# or digit. `keepers` locks the suffix to `env` — a rename regenerates.
# There is no soft-delete tombstone for the namespace name, so a destroyed
# name is reusable immediately.
resource "random_id" "suffix" {
  byte_length = 2 # 4 lowercase hex chars

  keepers = {
    env = var.env
  }
}

# -----------------------------------------------------------------------------
# Service Bus namespace
# -----------------------------------------------------------------------------
# Name pattern: sb-<env>-msg-<random> (e.g. "sb-dev-msg-a7f2"). With a
# 10-char env cap + "sb-" + "-msg-" + 4-char random = ≤ 22 chars,
# comfortably under the 50-char ceiling.
resource "azurerm_servicebus_namespace" "this" {
  name                = "sb-${var.env}-${local.purpose}-${random_id.suffix.hex}"
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
# move if we want per-app isolation; downstream module 11 doesn't care
# because it consumes queue names, not role assignments.
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
