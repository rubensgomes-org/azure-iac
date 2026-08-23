# modules/service-bus/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# SKU (`Standard`), `local_auth_enabled = true`, and other posture flags are
# HARD-CODED in main.tf as locals. Bumping to `Premium` (dedicated capacity,
# private endpoints, geo-DR) or flipping local auth off is a deliberate
# design change — not a per-environment knob.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). Baked into the namespace name
    (`sb-<env>-msg-<random>`) and drives the random-suffix keeper.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the Service Bus namespace. Must match the location of
    the RG passed via `resource_group_name`.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the namespace. Caller supplies `rg-<env>-data`
    (from module 01's outputs via `data.terraform_remote_state`). Data RG
    is the right home — Service Bus lifecycle is aligned with PostgreSQL
    and Storage (protected from `app` RG churn).
  EOT
  type        = string
}

variable "uami_principal_id" {
  description = <<-EOT
    Entra ID object ID (principal_id) of the shared UAMI created in module
    04. Used as the RBAC principal for the two role assignments granted at
    the namespace scope: `Azure Service Bus Data Sender` and
    `Azure Service Bus Data Receiver`. Container Apps then send/receive
    messages via `DefaultAzureCredential` — no SAS keys.
  EOT
  type        = string
}

variable "queues" {
  description = <<-EOT
    Queue names to create inside the namespace. One `azurerm_servicebus_queue`
    is created per name. Empty list = no queues (namespace + RBAC still
    provisioned).

    Kept as a first-class variable rather than deriving from `var.apps`
    because queues are communication channels *between* apps, not per-app
    resources — a two-app estate might share one queue, or an app might own
    several. Downstream module 11 (container-apps) will inject the relevant
    queue names into each app's env vars explicitly.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for q in var.queues : can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,258}[a-zA-Z0-9]$", q))])
    error_message = "Each queue name must be 1-260 chars, alphanumeric plus `.`, `_`, `-`, starting and ending with alphanumeric (Service Bus queue naming rules)."
  }
}

variable "tags" {
  description = <<-EOT
    Tags applied to the namespace. Merged with a module-local `component`
    tag for cost / graph queries.
  EOT
  type        = map(string)
  default     = {}
}
