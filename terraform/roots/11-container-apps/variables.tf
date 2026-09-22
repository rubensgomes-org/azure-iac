# roots/11-container-apps/variables.tf
# -----------------------------------------------------------------------------
# Root variables. Values come from `../../envs/<env>/env.tfvars` (shared,
# passed via -var-file). This module's own overrides (per-app image, target
# port, replicas) are TF_VAR_ exports -- this root is shared by every
# environment, so it can hold no `terraform.tfvars` of its own.
#
# Every variable defined in env.tfvars is declared here — even ones this
# module does not consume — because Terraform emits a warning for each
# undeclared variable it encounters in a -var-file. Declaring them all
# keeps plan/apply output clean.
# -----------------------------------------------------------------------------

# ---- Consumed by this module (from env.tfvars) ------------------------------

variable "env" {
  description = "Environment name. Sourced from ../../envs/<env>/env.tfvars."
  type        = string
}

variable "apps" {
  description = <<-EOT
    Microservice names. One Container App per entry. Sourced from
    ../../envs/<env>/env.tfvars.
  EOT
  type        = list(string)
}

variable "tags" {
  description = "Common tag map. Applied to every Container App. Per-run override; committed defaults live in ../../envs/<env>/tags.json."
  type        = map(string)
  default     = {}
}

# Contact stamped into the `owner` tag. Declared here — not just read from
# `../../envs/<env>/tags.json` — because Terraform silently drops `TF_VAR_*`
# for variables a module does not declare, so without this declaration
# `TF_VAR_owner` would be ignored outside bootstrap-backend. `null` rather
# than a literal default so an unset environment falls through to the
# committed value in that file instead of shadowing it; see locals.tf for the
# merge.
variable "owner" {
  description = "Contact for the `owner` tag. Overrides ../../envs/<env>/tags.json when set."
  type        = string
  default     = null
}

# ---- Consumed by this module (from TF_VAR_ overrides) -----------------------

variable "apps_image_map" {
  description = <<-EOT
    Optional per-app image reference override. Map from app name → full
    image reference (e.g. `<acr>.azurecr.io/api:1.2.3`). Any app not
    present in this map falls back to `var.default_image`. Export as
    TF_VAR_apps_image_map once real images exist in ACR.
  EOT
  type        = map(string)
  default     = {}
}

variable "default_image" {
  description = <<-EOT
    Fallback image used for any app not listed in `apps_image_map`.
    Default (in the child module) is `mcr.microsoft.com/k8se/quickstart:latest`,
    the Azure Container Apps quickstart placeholder. Export
    TF_VAR_default_image if you want a different placeholder for every
    unmapped app.
  EOT
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "target_port" {
  description = <<-EOT
    TCP port the container listens on. `80` matches the quickstart
    placeholder image; Spring Boot images typically use `8080`. Export
    TF_VAR_target_port when swapping to real images.
  EOT
  type        = number
  default     = 80
}

variable "health_probe_paths" {
  description = <<-EOT
    Optional map from app name → HTTP health path (e.g.
    `{"mathmcp":"/health"}`). Listed apps get HTTP probes; others keep
    ACA's default TCP probe. Export as TF_VAR_health_probe_paths.
  EOT
  type        = map(string)
  default     = {}
}

variable "cpu" {
  description = "Per-container vCPU allocation. Default 0.25 (Consumption minimum)."
  type        = number
  default     = 0.25
}

variable "memory" {
  description = "Per-container memory. Default 0.5Gi (pairs with cpu = 0.25)."
  type        = string
  default     = "0.5Gi"
}

variable "min_replicas" {
  description = "Minimum replica count. 0 = scale-to-zero when idle."
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Maximum replica count per app. Container Apps caps at 300."
  type        = number
  default     = 1
}

variable "ingress_external_enabled" {
  description = "true = each app gets an FQDN on the environment's static IP; false = ingress internal to the environment. Default false matches this environment's `internal_load_balancer_enabled = true`."
  type        = bool
  default     = false
}

# ---- Declared for env.tfvars parity, unused by this module -----------------

# CAF workload token, folded into most resource names elsewhere in the
# estate — see docs/NAMING.md. Container apps are a named exception (`ca-
# <app>-<env>`, no workload token), so this module has nothing to forward
# it to. Still declared here so `-var-file`'s env.tfvars `workload` key
# doesn't warn as undeclared.
variable "workload" {
  description = "CAF workload token. Not used here — Container Apps omit workload from their name. Declared for env.tfvars parity."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region. Not used here — Container Apps inherit region from the environment. Declared for env.tfvars parity."
  type        = string
  default     = null
}

variable "pg_entra_admin_group_object_id" {
  description = "Entra group object ID for PG admin. Not used here; consumed by 09-postgresql."
  type        = string
  default     = null
}

variable "pg_entra_admin_group_name" {
  description = "Entra group display name for PG admin. Not used here; consumed by 09-postgresql."
  type        = string
  default     = null
}

# ---- Remote-state backend coordinates -------------------------------------
# Where this root READS other roots' state from, i.e. the `config` block of
# every `data "terraform_remote_state"` below in main.tf. These are the same
# three values `../../envs/<env>/backend.hcl` supplies to `terraform init`
# for this root's OWN state -- a backend block cannot take variables, so the
# two are declared separately and MUST agree.
#
# Required, with no defaults, and that is deliberate. The roots under
# terraform/roots/ are shared by every environment, so a default here can
# only ever name one of them. While the roots lived under envs/dev/ a default
# pointing at the dev backend was merely redundant; shared, it becomes a
# silent cross-environment read -- `init` attaches to the container named by
# the environment's own backend.hcl while every remote-state read below falls
# through to the default, handing this plan another environment's RG names
# and subnet IDs. Nothing errors. The estate just comes out wired to the
# wrong place.
#
# Supply all three as TF_VAR_backend_resource_group_name /
# TF_VAR_storage_account_id / TF_VAR_container_name -- the names
# docs/INITIAL_SETUP.md already tells you to export, and the ones both CI
# workflows bind. Miss one and Terraform stops with "No value for required
# variable", naming it.
#
# Deliberately NOT in `../../envs/<env>/env.tfvars`: `-var-file` outranks
# TF_VAR_*, so a value there would silently defeat the CI override -- the
# trap env.tfvars.example documents at the top of the file. `workload` sits on
# the other side of that line, in env.tfvars, precisely because it is meant to
# be per-environment and pinned rather than overridable from the shell.

variable "backend_resource_group_name" {
  description = "Resource group owning the tfstate storage account. Must match the environment's backend.hcl."
  type        = string
}

variable "storage_account_id" {
  description = "Name of the storage account holding the tfstate container. Must match the environment's backend.hcl."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_id))
    error_message = "storage_account_id must be 3-24 lowercase letters/digits."
  }
}

variable "container_name" {
  description = "Blob container holding every root's state blob. Must match the environment's backend.hcl."
  type        = string
}
