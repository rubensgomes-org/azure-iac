# modules/storage/main.tf
# -----------------------------------------------------------------------------
# Provisions one shared storage account per env plus:
#   - the RBAC grant that lets the shared UAMI read/write blobs,
#   - one blob container per app in `var.apps`.
#
# No current consumer wires this module's outputs in — the shared UAMI
# already holds the RBAC grant, so a future consumer only needs `sa_name`
# and `container_names` via `data.terraform_remote_state`.
#
# The passwordless model means we NEVER enable shared-key auth. Setting
# `shared_access_key_enabled = true` would allow the classic
# `AccountName=...;AccountKey=...` connection string — the opposite of the
# design.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# SKU + posture (locals)
# -----------------------------------------------------------------------------
# - `Standard_LRS`: cheapest tier, single-region redundancy. GRS/ZRS are
#   overkill for a playground and cost more.
# - `StorageV2` general-purpose: supports Blob + File + Queue + Table so we
#   can extend later without recreating the account.
# - `Hot` access tier: reads are cheap, writes are dominant in dev.
# - `shared_access_key_enabled = false`: forces AAD auth for every data-plane
#   call. No account keys land in state, KV, or app env vars.
# - `public_network_access_enabled = true`: matches the playground posture.
#   Move to `false` + a PE against `privatelink.blob.core.windows.net`
#   (zone from module 02) later if we want network isolation.
# - `allow_nested_items_to_be_public = false`: even if a container were
#   accidentally created with public access, blobs stay private.
# - Soft delete = 2 days for both blobs AND containers: shortest tolerable
#   recovery window. 0 disables entirely; anything higher hoards state.
locals {
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = true
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  soft_delete_retention_days      = 2
  purpose                         = "app"
}

# -----------------------------------------------------------------------------
# Storage Account
# -----------------------------------------------------------------------------
# Name pattern: st<workload>app<env> (e.g. "strgomesapplab").
#
# This is the one resource where the CAF `<type>-<workload>-<env>` form cannot
# be spelled with its dashes: storage account names are lowercase alphanumeric
# ONLY (no dashes, no underscores), 3-24 chars. The three tokens are therefore
# run together in the same order, with the `app` purpose folded onto the
# workload token exactly as it is elsewhere in the estate.
#
# 24 chars is the tightest budget anywhere here, and `workload` (≤16) + "app"
# + `env` (≤10) + "st" can reach 31 — hence the precondition below rather than
# trusting the two variable validations separately.
#
# No random suffix: names are deterministic estate-wide. Storage account names
# are globally unique across every Azure tenant, so this can collide with a
# stranger's account — the trade the estate accepts for derivable names. There
# is no soft-delete tombstone on the account name itself, so unlike Key Vault
# and Log Analytics a destroyed name is reusable immediately.
resource "azurerm_storage_account" "this" {
  name                = "st${var.workload}${local.purpose}${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name

  account_tier             = local.account_tier
  account_replication_type = local.account_replication_type
  account_kind             = local.account_kind
  access_tier              = local.access_tier

  min_tls_version                 = local.min_tls_version
  https_traffic_only_enabled      = local.https_traffic_only_enabled
  public_network_access_enabled   = local.public_network_access_enabled
  shared_access_key_enabled       = local.shared_access_key_enabled
  allow_nested_items_to_be_public = local.allow_nested_items_to_be_public

  blob_properties {
    delete_retention_policy {
      days = local.soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = local.soft_delete_retention_days
    }
  }

  tags = merge(
    var.tags,
    { component = "storage" },
  )

  # The tightest name budget in the estate, and the only one with no dashes to
  # make the overflow obvious on sight. `workload` (≤16) and `env` (≤10)
  # validate independently, so a legal pair can compose a 31-char name that
  # Azure rejects at apply time with an opaque error. Fail at plan time
  # instead, naming the offending value.
  lifecycle {
    precondition {
      condition     = length("st${var.workload}${local.purpose}${var.env}") <= 24
      error_message = "Storage account name st${var.workload}${local.purpose}${var.env} exceeds 24 chars. Shorten workload or env."
    }
  }
}

# -----------------------------------------------------------------------------
# RBAC — Storage Blob Data Contributor for the shared UAMI
# -----------------------------------------------------------------------------
# Contributor (not Reader) so apps can write blobs, not just read. Scope is
# the STORAGE ACCOUNT — every container inherits. Tightening to per-container
# scope is a future move if we want per-app isolation; a future consumer
# would only need the container names, not the role assignment itself.
#
# `principal_type = "ServicePrincipal"` avoids a slow Entra lookup on every
# plan — UAMIs surface as service principals. Skipping this makes Terraform
# infer the type, which occasionally fails on brand-new identities (Entra
# hasn't propagated yet).
resource "azurerm_role_assignment" "uami_blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.uami_principal_id
  principal_type       = "ServicePrincipal"
}

# -----------------------------------------------------------------------------
# Blob containers (one per app) — via ARM control plane
# -----------------------------------------------------------------------------
# `azurerm_storage_container` would use the blob data plane, which — with
# `shared_access_key_enabled = false` — requires the Terraform SP to hold
# `Storage Blob Data Contributor` on the SA AND requires a wait for RBAC to
# propagate (typical 30-60s). Using `azapi_resource` instead routes the
# create call through ARM (`Microsoft.Storage/.../containers`), which the
# Terraform SP already has Contributor on via bootstrap — no data-plane
# grant, no propagation wait.
#
# `publicAccess = None`: blobs are never anonymously reachable; AAD auth is
# the only path in. Container name is the app name (matches env-var wiring
# in module 11).
resource "azapi_resource" "container" {
  for_each = toset(var.apps)

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = each.key
  parent_id = "${azurerm_storage_account.this.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}
