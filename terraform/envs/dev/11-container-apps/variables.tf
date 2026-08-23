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
  description = "Common tag map. Applied to every Container App. Sourced from ../env.tfvars."
  type        = map(string)
  default     = {}
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
