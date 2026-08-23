# modules/service-bus

Child Terraform module that provisions the shared Azure Service Bus
namespace per environment, optional queues, and the two RBAC role
assignments (`Azure Service Bus Data Sender` and `Data Receiver`) that
let the shared UAMI send and receive messages passwordlessly.

Called by `terraform/envs/dev/08-service-bus/`. State is owned by the
caller — this module has no `backend` block.

## Resources created

| Type                       | Name                                      | Notes                                                                                                    |
|----------------------------|-------------------------------------------|----------------------------------------------------------------------------------------------------------|
| `random_id`                | `suffix`                                  | 4-hex-char suffix; keyed on `env`.                                                                       |
| `azurerm_servicebus_namespace` | `sb-<env>-msg-<random>`               | `Standard` SKU, TLS 1.2, public network on, local auth on (flip to off once every app is passwordless).  |
| `azurerm_role_assignment`  | `Azure Service Bus Data Sender` for UAMI  | Scope: namespace.                                                                                        |
| `azurerm_role_assignment`  | `Azure Service Bus Data Receiver` for UAMI| Scope: namespace.                                                                                        |
| `azurerm_servicebus_queue` | one per `var.queues`                      | All queue settings at Azure defaults.                                                                    |

## Inputs

| Name                  | Type           | Required | Notes                                                                                            |
|-----------------------|----------------|----------|--------------------------------------------------------------------------------------------------|
| `env`                 | `string`       | yes      | Baked into name and random keeper. `^[a-z][a-z0-9]{1,9}$`.                                       |
| `location`            | `string`       | yes      | Azure region. Must match the RG's location.                                                      |
| `resource_group_name` | `string`       | yes      | Caller passes `rg-<env>-data` (from module 01).                                                  |
| `uami_principal_id`   | `string`       | yes      | `principal_id` of the shared UAMI (from module 04).                                              |
| `queues`              | `list(string)` | no       | Queue names to create. Default `[]`.                                                             |
| `tags`                | `map(string)`  | no       | Merged with `component = "service-bus"`.                                                         |

## Outputs

- `sb_namespace_id` — full Azure Resource ID
- `sb_namespace_name` — namespace name
- `sb_namespace_fqdn` — `<name>.servicebus.windows.net`
- `sb_namespace_endpoint` — `sb://<name>.servicebus.windows.net/`
- `sb_location`
- `sb_sender_role_assignment_id`, `sb_receiver_role_assignment_id`
- `sb_queue_names` — map `{ <queue> => <queue> }`
- `sb_queue_ids` — map `{ <queue> => <full-resource-id> }`

## Design decisions

- **`Standard` SKU.** Cheapest tier that supports topics/subscriptions in
  addition to queues, plus roomier limits than `Basic`. `Premium`
  (dedicated capacity, PE, geo-DR) is overkill and ~100× the cost.
- **`local_auth_enabled = true`.** SAS keys stay reachable at the
  namespace for now. Every *app* still uses AAD via the shared UAMI (the
  Data Sender / Data Receiver roles) — local auth exists as a debugging
  escape hatch (`az servicebus namespace authorization-rule keys list`)
  during first-run bring-up. Flip to `false` once every app is confirmed
  passwordless; see `docs/PROVISIONING_PLAN.md` §9.
- **Public network enabled.** Playground posture, matches ACR/KV/Storage.
  Move to private endpoint (add the `privatelink.servicebus.windows.net`
  zone in module 02) if we want network isolation.
- **TLS 1.2 minimum.** Rejects legacy clients; no old SDK will run here.
- **Two role assignments (Sender + Receiver) at namespace scope.** Every
  queue (and future topic/subscription) inherits — dev-friendly, one pair
  of assignments covers the whole namespace. Tighten to per-queue scope
  later if we want per-app isolation. Trade-off flagged in
  `docs/PROVISIONING_PLAN.md` §12 (shared blast radius across apps).
- **Queues via a separate `queues` variable (not `var.apps`).** Queues
  are communication channels *between* apps, not per-app resources. A
  two-app estate might share one queue, or an app might own several.
  Decoupling from `apps` keeps queue topology flexible without churning
  the microservice list. Default `[]` — the namespace stands up cleanly
  with no queues.
- **Queue settings left at Azure defaults.** 1 GiB max size, 14-day TTL,
  60s lock, delivery count 10, no DLQ on expiration. Tune per queue
  later when a specific workload needs it.

## Skipped dependencies (vs. the plan)

`docs/PROVISIONING_PLAN.md` §4 lists module 05 (Key Vault) as a
service-bus dependency. There is no structural dep in the current
design:

- **05 Key Vault:** No customer-managed key for encryption-at-rest —
  the Microsoft-managed key covers dev. No SAS key to stash in KV
  (apps auth via AAD). If we add CMK later, wire remote state to
  module 05.

## Downstream consumers

- **Container Apps (module 11):** each `azurerm_container_app` gets env
  var `SERVICEBUS_NAMESPACE_FQDN = <sb_namespace_fqdn>` plus whichever
  queue name(s) that app cares about. Apps authenticate via
  `DefaultAzureCredential` — no SAS keys, no connection strings.
