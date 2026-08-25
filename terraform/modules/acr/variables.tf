# modules/acr/variables.tf
# -----------------------------------------------------------------------------
# Inputs consumed by main.tf.
#
# SKU (`Basic`) and `admin_enabled = false` are HARD-CODED in main.tf as
# locals. Bumping to Standard/Premium is a deliberate design change (needed
# for private endpoints, geo-replication, or content trust) — not a
# per-environment knob.
# -----------------------------------------------------------------------------

variable "acr_name" {
  description = <<-EOT
    Registry name. Explicit and required — this module does NOT derive it
    from `env` and appends no random suffix, because the registry name is
    typed constantly (image tags, `docker push`, `az acr`, `apps_image_map`)
    and must stay stable across destroy+recreate.

    ACR names are GLOBALLY unique across every Azure tenant and allow
    alphanumeric characters ONLY — no dashes, no underscores, 5-50 chars.
    Verify availability with `az acr check-name -n <name>` before setting a
    new one. Dev uses "rubensdevacr" (set in the root's terraform.tfvars).
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must be 5-50 alphanumeric characters — no dashes, underscores, or other punctuation."
  }
}

variable "env" {
  description = <<-EOT
    Environment name (e.g. "dev", "prod"). No longer part of the registry
    name (see `acr_name`) — retained because the caller passes it for tag
    and convention parity with every other module.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.env))
    error_message = "env must be 2-10 lowercase alnum chars starting with a letter."
  }
}

variable "location" {
  description = <<-EOT
    Azure region for the registry. Must match the location of the RG passed
    via `resource_group_name`.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the RG that holds the registry. Caller supplies
    `rg-<env>-platform` (from module 01's outputs via
    `data.terraform_remote_state`). Platform RG is the right home — ACR is
    long-lived and shared across workloads.
  EOT
  type        = string
}

variable "uami_principal_id" {
  description = <<-EOT
    Entra ID object ID (principal_id) of the shared UAMI created in module
    04. Used as the RBAC principal for the `AcrPull` role assignment at
    registry scope — Container Apps use this identity for passwordless
    image pulls.
  EOT
  type        = string
}

variable "tags" {
  description = <<-EOT
    Tags applied to the registry. Merged with a module-local `component`
    tag for cost / graph queries.
  EOT
  type        = map(string)
  default     = {}
}
