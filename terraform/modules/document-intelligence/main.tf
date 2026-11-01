# modules/document-intelligence/main.tf
# -----------------------------------------------------------------------------
# Provisions an Azure AI Document Intelligence resource (`kind =
# FormRecognizer`), a "Cognitive Services User" grant for the shared UAMI,
# and a storage account with a `training` container for custom models.
#
# Design decisions (fixed here, not variables):
#
# * **S0 SKU.** F0 is limited to one per subscription.
#
# * **Entra ID only.** `local_auth_enabled = false` disables API keys.
#
# * **Custom subdomain = resource name.** Required for Entra ID auth. The
#   subdomain is globally unique and held by a soft-deleted resource until
#   purged; the calling root purges on destroy.
#
# * **Training storage.** Same posture as modules/storage (no shared keys,
#   no public blobs). The CORS rule lets Document Intelligence Studio read
#   and write labels from the browser.
# -----------------------------------------------------------------------------

module "region_code" {
  source   = "../region-code"
  location = var.location
}

locals {
  account_name = "di-${var.workload}ai-${var.env}-${module.region_code.code}"

  kind     = "FormRecognizer"
  sku_name = "S0"

  cognitive_services_user_role_id = "a97b65f3-24c7-4388-baec-2e87135dc908"

  storage_account_name       = "st${var.workload}di${var.env}${module.region_code.code}"
  training_container_name    = "training"
  soft_delete_retention_days = 2

  studio_origin        = "https://documentintelligence.ai.azure.com"
  studio_methods       = ["DELETE", "GET", "HEAD", "MERGE", "OPTIONS", "PATCH", "POST", "PUT"]
  cors_max_age_seconds = 120
}

data "azurerm_client_config" "current" {}

resource "azurerm_cognitive_account" "this" {
  name                  = local.account_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  kind                  = local.kind
  sku_name              = local.sku_name
  custom_subdomain_name = local.account_name
  local_auth_enabled    = false

  identity {
    type = "SystemAssigned"
  }

  tags = merge(
    var.tags,
    { component = "document-intelligence" },
  )
}

resource "azurerm_role_assignment" "uami_cognitive_services_user" {
  scope              = azurerm_cognitive_account.this.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.cognitive_services_user_role_id}"
  principal_id       = var.uami_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_storage_account" "training" {
  name                = local.storage_account_name
  location            = var.location
  resource_group_name = var.resource_group_name

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = true
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false

  blob_properties {
    cors_rule {
      allowed_origins    = [local.studio_origin]
      allowed_methods    = local.studio_methods
      allowed_headers    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = local.cors_max_age_seconds
    }
    delete_retention_policy {
      days = local.soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = local.soft_delete_retention_days
    }
  }

  tags = merge(
    var.tags,
    { component = "document-intelligence" },
  )

  lifecycle {
    precondition {
      condition     = length(local.storage_account_name) <= 24
      error_message = "Storage account name ${local.storage_account_name} exceeds 24 chars. Shorten workload or env."
    }
  }
}

# ARM control plane, so the Terraform SP needs no data-plane grant; see
# modules/storage.
resource "azapi_resource" "training_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = local.training_container_name
  parent_id = "${azurerm_storage_account.training.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

# Document Intelligence reads training data with its system identity.
resource "azurerm_role_assignment" "di_blob_reader" {
  scope                = azurerm_storage_account.training.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_cognitive_account.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "uami_blob_contributor" {
  scope                = azurerm_storage_account.training.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.uami_principal_id
  principal_type       = "ServicePrincipal"
}

# Studio writes label files with the signed-in user's Entra token.
resource "azurerm_role_assignment" "user_blob_contributor" {
  count = var.di_user_object_id == null ? 0 : 1

  scope                = azurerm_storage_account.training.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.di_user_object_id
  principal_type       = "User"
}
