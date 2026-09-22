# modules/container-apps/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# Every microservice in `var.apps` becomes one `azurerm_container_app` named
# `ca-<app>-<env>`, all sharing:
#   - the same Container App Environment (`var.container_app_environment_id`),
#   - the same UAMI (`var.uami_id`) for runtime identity AND ACR pull,
#   - the same Key Vault (`var.key_vault_uri`) for secrets.
#
# Fixed design decisions (Consumption workload profile, single-revision mode,
# internal ingress by default, scale-to-zero) live in main.tf as locals or
# hard-coded fields with an explanatory comment. Things that could reasonably
# vary per app or per env (image reference, replica counts, target port,
# CPU/memory) are variables.
#
# See the module README for the passwordless wiring this module
# implements.
# -----------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (e.g. "lab", "dev", "prod"). Trailing token of every
    container app name: ca-<app>-<env>.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the container apps. Caller supplies
    `rg-<env>-app` (from module 01's outputs via
    `data.terraform_remote_state`) — the same RG that holds the Container
    App Environment, so app + environment lifecycle stay aligned.
  EOT
  type        = string
}

variable "container_app_environment_id" {
  description = <<-EOT
    Full Azure Resource ID of the ACAE that hosts these apps. Caller
    supplies `cae_id` from module 10's remote state. Container Apps refuse
    to create if the environment is in a Failed/Deleting state — check
    `az containerapp env show` first if apply errors on this field.
  EOT
  type        = string
}

variable "apps" {
  description = <<-EOT
    List of microservice names. One `azurerm_container_app` is created per
    entry, keyed by `for_each = toset(var.apps)`. Names appear in the
    resource name (`ca-<app>-<env>`), the `app` tag, and are used as the
    default key when looking up per-app values in `var.apps_image_map`.

    Each name must be a valid Container App name suffix: 2-27 chars,
    lowercase alnum + hyphens, starting with a letter. With the
    `ca-` prefix and `-<env>` suffix (at most 4 chars for env="dev") that
    keeps the full name under Azure's 32-char cap.
  EOT
  type        = list(string)

  validation {
    condition     = alltrue([for a in var.apps : can(regex("^[a-z][a-z0-9-]{1,26}$", a))])
    error_message = "Each app name must be 2-27 lowercase alnum chars (or hyphens) starting with a letter."
  }
}

variable "uami_id" {
  description = <<-EOT
    Full Azure Resource ID of the shared UAMI (module 04). Attached to
    every app via `identity.identity_ids` AND used as the ACR pull identity
    (`registry.identity`). Same identity, two uses — no per-app RBAC
    ceremony.
  EOT
  type        = string
}

variable "uami_client_id" {
  description = <<-EOT
    OAuth client ID of the shared UAMI (module 04). Injected as
    `AZURE_CLIENT_ID` on every app so `DefaultAzureCredential` picks THIS
    identity when the container has (or will later gain) more than one
    managed identity attached. Without it, DAC may pick the wrong
    identity and fail auth silently.
  EOT
  type        = string
}

variable "acr_login_server" {
  description = <<-EOT
    Registry login server (`<acr>.azurecr.io`, from module 06). Passed to
    the `registry.server` block on every app so pulls from that ACR use
    the shared UAMI (via `registry.identity`). Images referenced from
    other registries (e.g. `mcr.microsoft.com/...`, the default
    placeholder) are pulled anonymously — the `registry` block only
    applies to images whose repo matches the server.
  EOT
  type        = string
}

variable "key_vault_uri" {
  description = <<-EOT
    Vault DNS URI (`https://<name>.vault.azure.net/`, from module 05).
    Injected as `KEY_VAULT_URI` on every app so app code can build a
    `SecretClient` and fetch secrets via `DefaultAzureCredential`. RBAC
    (`Key Vault Secrets User`) on the shared UAMI was already granted in
    module 05.
  EOT
  type        = string
}

variable "apps_image_map" {
  description = <<-EOT
    Optional per-app image override. Map from app name → full image
    reference (e.g. `<acr>.azurecr.io/api:1.2.3`). Any app not present in
    this map falls back to `var.default_image`.

    Deployed as-is — no tag mutation. Bump the tag here to roll a new
    revision; Terraform will replace the running revision on next apply.
  EOT
  type        = map(string)
  default     = {}
}

variable "default_image" {
  description = <<-EOT
    Fallback image reference used for any app not listed in
    `var.apps_image_map`. Default is the Azure Container Apps quickstart
    image (`mcr.microsoft.com/k8se/quickstart:latest`) — a public,
    always-available "hello world" listening on port 80. Real Java /
    Spring Boot images land in `apps_image_map` once they're pushed to
    ACR; until then, this placeholder keeps `terraform apply` green even
    with an empty ACR.
  EOT
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "target_port" {
  description = <<-EOT
    TCP port the container listens on. Matched by the ingress block so
    Azure routes external traffic to it. `80` matches the quickstart
    placeholder image; Java / Spring Boot images typically listen on
    `8080` — override with `TF_VAR_target_port` when swapping to a real
    image.
  EOT
  type        = number
  default     = 80

  validation {
    condition     = var.target_port > 0 && var.target_port < 65536
    error_message = "target_port must be a valid TCP port (1-65535)."
  }
}

variable "cpu" {
  description = <<-EOT
    Per-container CPU allocation in vCPU units. `0.25` is the minimum
    Consumption-plan value (the smallest cost knob for a playground).
    Must pair with a compatible `memory` value — Container Apps enforces
    a fixed set of CPU/memory combos (`0.25 vCPU + 0.5 Gi`,
    `0.5 vCPU + 1 Gi`, etc.).
  EOT
  type        = number
  default     = 0.25
}

variable "memory" {
  description = <<-EOT
    Per-container memory allocation, as a string with a `Gi` suffix
    (e.g. `"0.5Gi"`, `"1Gi"`, `"2Gi"`). Default `"0.5Gi"` pairs with
    `cpu = 0.25`. See the Container Apps documentation for the full
    valid CPU/memory pair table.
  EOT
  type        = string
  default     = "0.5Gi"
}

variable "min_replicas" {
  description = <<-EOT
    Minimum replica count per app. Default `0` = scale-to-zero when idle
    (no ingress traffic for 5 minutes). First request after idle incurs
    a cold-start latency (~seconds). Set to `1` for latency-sensitive
    apps.
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.min_replicas >= 0
    error_message = "min_replicas must be >= 0."
  }
}

variable "max_replicas" {
  description = <<-EOT
    Maximum replica count per app. Default `1` = no horizontal scale-out
    (single instance handles all traffic). Bump per app once a scale rule
    is in place. Container Apps caps at 300 per app.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 300
    error_message = "max_replicas must be between 1 and 300 (Container Apps ceiling)."
  }
}

variable "ingress_external_enabled" {
  description = <<-EOT
    `true` exposes each app on the environment's static IP with an
    auto-assigned FQDN (`<app>.<cae_default_domain>`) — reachable from
    the VNet, or the internet if the environment also has
    `internal_load_balancer_enabled = false`. `false` keeps ingress
    internal to the environment (reachable only from other apps on the
    delegated subnet). Default `false`: this environment provisions with
    `internal_load_balancer_enabled = true`, so apps stay internal-only
    unless a workload needs cross-app-boundary reachability.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = <<-EOT
    Tags applied to every container app. Merged with per-app tags
    (`component = "container-app"`, `app = <name>`) for cost / graph
    queries.
  EOT
  type        = map(string)
  default     = {}
}
