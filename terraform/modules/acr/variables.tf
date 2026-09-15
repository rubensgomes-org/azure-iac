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
    Registry name. Explicit and required — this module does NOT compose it
    from `workload` + `env` the way every other name in the estate is composed,
    because the registry name is typed constantly (image tags, `docker push`,
    `az acr`, `apps_image_map`) and must stay stable and human-chosen.

    Follow the CAF convention anyway, spelled without the dashes ACR forbids:
    `cr<workload><env>`, e.g. "crrgomeslab". See docs/NAMING.md for why this
    one name is an exception.

    ACR names are GLOBALLY unique across every Azure tenant and allow
    alphanumeric characters ONLY — no dashes, no underscores, 5-50 chars.
    Verify availability with `az acr check-name -n <name>` before setting a
    new one. Dev uses "crrgomesdev01" and lab uses "crrgomeslab02", supplied
    as TF_VAR_acr_name.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must be 5-50 alphanumeric characters — no dashes, underscores, or other punctuation."
  }
}

variable "workload" {
  description = <<-EOT
    Workload token in the CAF name `<type>-<workload>-<env>`, e.g. "rgomes"
    produces crrgomeslab (the convention for `acr_name`).
    NOT used to compose a name here — `acr_name` is supplied verbatim, the
    estate's one exception to the CAF rule. Declared so every module in the
    estate takes the same input set, and so the value is available if this
    module ever composes its own name.

    `name` is ForceNew on every resource named from it, so changing this on a
    live estate is a destroy+recreate, not a rename. Set it at first provision,
    or after a full teardown. See docs/NAMING.md.
  EOT
  type        = string
  default     = "rgomes"

  # `nullable = false` is load-bearing, not decoration. Every root declares
  # `workload` with `default = null` so an env.tfvars that omits it falls
  # through to this default -- but a null passed to a nullable variable is a
  # VALUE, not an absence, so without this the fall-through hits the validation
  # below and fails with "workload must be 2-16 lowercase alnum chars" naming
  # nothing. With it, Terraform substitutes this default before validating.
  nullable = false

  validation {
    # Lowercase alnum, 2-16 chars — the same shape enforced by every module, so
    # one value can name the whole estate. The ceiling is set by the tightest
    # consumer, the storage account name (st<workload><purpose><env>, 24 chars,
    # no dashes). The leading letter avoids a name that looks numeric.
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.workload))
    error_message = "workload must be 2-16 lowercase alnum chars starting with a letter."
  }
}

variable "env" {
  description = <<-EOT
    Environment name (e.g. "lab", "dev", "prod"). Not baked into the registry
    name — `acr_name` is supplied verbatim — but kept for parity with every
    other module and available for tags.
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
