# envs/dev/11-container-apps/variables.tf
# -----------------------------------------------------------------------------
# Root variables. Values come from `../env.tfvars` (shared, passed via
# -var-file) plus this root's own `terraform.tfvars` for module-specific
# overrides (per-app image, target port, replicas).
#
# Every variable defined in env.tfvars is declared here — even ones this
# module does not consume — because Terraform emits a warning for each
# undeclared variable it encounters in a -var-file. Declaring them all
# keeps plan/apply output clean.
# -----------------------------------------------------------------------------

# ---- Consumed by this module (from ../env.tfvars) --------------------------

variable "env" {
  description = "Environment name. Sourced from ../env.tfvars."
  type        = string
}

variable "apps" {
  description = <<-EOT
    Microservice names. One Container App per entry. Must match the list
    used by modules 07 (blob containers) and 09 (PG databases) — those
    modules created the per-app resources whose names get injected here.
    Sourced from ../env.tfvars.
  EOT
  type        = list(string)
}

variable "tags" {
  description = "Common tag map. Applied to every Container App. Per-run override; committed defaults live in ../tags.json."
  type        = map(string)
  default     = {}
}

# Contact stamped into the `owner` tag. Declared here — not just read from
# `../tags.json` — because Terraform silently drops `TF_VAR_*` for variables a
# module does not declare, so without this declaration `TF_VAR_owner` would be
# ignored outside bootstrap-backend. `null` rather than a literal default so an
# unset environment falls through to the committed value in `../tags.json`
# instead of shadowing it; see locals.tf for the merge.
variable "owner" {
  description = "Contact for the `owner` tag. Overrides ../tags.json when set."
  type        = string
  default     = null
}

# ---- Consumed by this module (from terraform.tfvars overrides) -------------

variable "apps_image_map" {
  description = <<-EOT
    Optional per-app image reference override. Map from app name → full
    image reference (e.g. `<acr>.azurecr.io/api:1.2.3`). Any app not
    present in this map falls back to `var.default_image`. Set in
    `terraform.tfvars` once real images exist in ACR.
  EOT
  type        = map(string)
  default     = {}
}

variable "default_image" {
  description = <<-EOT
    Fallback image used for any app not listed in `apps_image_map`.
    Default (in the child module) is `mcr.microsoft.com/k8se/quickstart:latest`,
    the Azure Container Apps quickstart placeholder. Override in
    `terraform.tfvars` if you want a different placeholder for every
    unmapped app.
  EOT
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "target_port" {
  description = <<-EOT
    TCP port the container listens on. `80` matches the quickstart
    placeholder image; Spring Boot images typically use `8080`. Override
    in `terraform.tfvars` when swapping to real images.
  EOT
  type        = number
  default     = 80
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
  description = "true = each app gets a public FQDN on the environment's static IP; false = ingress internal to the environment."
  type        = bool
  default     = true
}

# ---- Declared for env.tfvars parity, unused by this module -----------------

variable "location" {
  description = "Azure region. Not used here — Container Apps inherit region from the environment. Declared for env.tfvars parity."
  type        = string
  default     = null
}

variable "prefix" {
  description = "Owner/org token. Not used here; consumed by KV/ACR/etc. modules."
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
# three values `../backend.hcl` supplies to `terraform init` for this root's
# OWN state -- a backend block cannot take variables, so the two are declared
# separately and MUST agree.
#
# The defaults mirror ../backend.hcl so a local run needs no extra input. CI
# runners override them with TF_VAR_backend_resource_group_name /
# TF_VAR_storage_account_id / TF_VAR_container_name, which are the same names
# terraform/INITIAL_SETUP.md already tells you to export in your shell.
#
# Deliberately NOT in ../env.tfvars: `-var-file` outranks TF_VAR_*, so a value
# there would silently defeat the CI override -- the trap env.tfvars.example
# already documents for `rg_suffix`.

variable "backend_resource_group_name" {
  description = "Resource group owning the tfstate storage account. Must match ../backend.hcl."
  type        = string
  default     = "rg-tfstate"
}

variable "storage_account_id" {
  description = "Name of the storage account holding the tfstate container. Must match ../backend.hcl."
  type        = string
  default     = "sttfstaterubens01"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_id))
    error_message = "storage_account_id must be 3-24 lowercase letters/digits."
  }
}

variable "container_name" {
  description = "Blob container holding every root's state blob. Must match ../backend.hcl."
  type        = string
  default     = "tfstate"
}
