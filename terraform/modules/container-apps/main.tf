# modules/container-apps/main.tf
# -----------------------------------------------------------------------------
# Provisions one `azurerm_container_app` per entry in `var.apps`, all sharing:
#   - the same Container App Environment (module 10),
#   - the same UAMI (module 04) for BOTH runtime identity and ACR pull,
#   - the same PG server / Storage account / Service Bus namespace, with per-
#     app values (DB name, blob container) resolved from the maps modules 09
#     and 07 already produce.
#
# This is the module where the passwordless model finally comes
# together: every downstream service the apps consume was RBAC'd to the shared
# UAMI in its own module (05..09), and here we attach that identity and inject
# the env vars app code needs to reach each service via
# `DefaultAzureCredential`. No passwords, no keys, no connection strings.
#
# Design decisions fixed here (not variables):
#
# * **`revision_mode = "Single"`**: one active revision at a time. New
#   revisions replace the old immediately on apply. Simpler for a playground
#   than `Multiple` (which needs traffic-splitting rules).
#
# * **`registry.identity = <shared-uami>`**: passwordless ACR pull. The
#   registry block is declared unconditionally even when apps default to
#   `mcr.microsoft.com/...`; Azure only consults it for images whose repo
#   matches `registry.server`. Wiring it now keeps the flip to ACR-hosted
#   images a one-line variable change.
#
# * **`traffic_weight { latest_revision = true, percentage = 100 }`**: 100%
#   of traffic to the latest revision. Required by the platform when
#   `revision_mode = "Single"`; declaring it explicitly makes the intent
#   plain in the plan output.
#
# * **`transport = "auto"`**: lets Azure pick HTTP/1.1 or HTTP/2 based on
#   client. gRPC apps override to `"http2"` in a follow-on.
#
# * **Env vars, no `secret` blocks**: every value below is either a well-
#   known hostname or the UAMI's client_id. None are secrets — the UAMI
#   itself is the auth material, held by the platform.
#
# See the module README for the passwordless auth model and the
# per-service env-var contract.
# -----------------------------------------------------------------------------

resource "azurerm_container_app" "app" {
  for_each = toset(var.apps)

  name                         = "ca-${var.env}-${each.key}"
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  # Attach the SHARED UAMI. Same identity on every app — no per-app RBAC.
  # `type = "UserAssigned"` (not `SystemAssigned` and not `SystemAssigned,
  # UserAssigned`) means no system-assigned identity is created; the apps
  # only ever authenticate as `var.uami_name`.
  identity {
    type         = "UserAssigned"
    identity_ids = [var.uami_id]
  }

  # Passwordless ACR pull. The UAMI already holds `AcrPull` on this
  # registry (granted in module 06). See file header for why this block is
  # declared even when the placeholder image comes from `mcr.microsoft.com`.
  registry {
    server   = var.acr_login_server
    identity = var.uami_id
  }

  # Ingress. External by default so browsers can hit the apps at
  # `<app>.<cae_default_domain>`. Toggle via `var.ingress_external_enabled`.
  ingress {
    external_enabled = var.ingress_external_enabled
    target_port      = var.target_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = each.key
      image  = lookup(var.apps_image_map, each.key, var.default_image)
      cpu    = var.cpu
      memory = var.memory

      # Tells DefaultAzureCredential to select THIS UAMI when acquiring
      # tokens (matters as soon as more than one identity is attached).
      env {
        name  = "AZURE_CLIENT_ID"
        value = var.uami_client_id
      }

      # PG connection info. Password is intentionally absent — the app
      # fetches an AAD token via the SDK and passes it as the password
      # field in the libpq connection.
      env {
        name  = "POSTGRES_HOST"
        value = var.postgres_host
      }
      env {
        name  = "POSTGRES_DB"
        value = lookup(var.postgres_databases, each.key, each.key)
      }
      env {
        name  = "POSTGRES_USER"
        value = var.uami_name
      }

      # Storage: apps compose the blob endpoint from the account name and
      # use `DefaultAzureCredential` for auth. No account key, no SAS.
      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = var.storage_account_name
      }
      env {
        name  = "STORAGE_CONTAINER_NAME"
        value = lookup(var.storage_container_names, each.key, each.key)
      }

      # Service Bus: SDK targets the namespace FQDN + AAD credential.
      env {
        name  = "SERVICEBUS_NAMESPACE_FQDN"
        value = var.servicebus_namespace_fqdn
      }
    }
  }

  tags = merge(
    var.tags,
    {
      component = "container-app"
      app       = each.key
    },
  )
}
