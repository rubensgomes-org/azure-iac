# modules/ai-search/main.tf
# -----------------------------------------------------------------------------
# Provisions an Azure AI Search service and the storage account with a
# `documents` container that it indexes.
#
# Design decisions (fixed here, not variables):
#
# * **Basic SKU.** Free is limited to one per subscription and does not
#   support managed identity, which the blob indexer uses.
#
# * **Entra ID only.** `local_authentication_enabled = false` disables API
#   keys.
#
# * **Storage.** Same posture as modules/storage (no shared keys, no public
#   blobs).
# -----------------------------------------------------------------------------

module "region_code" {
  source   = "../region-code"
  location = var.location
}

locals {
  search_service_name = "srch-${var.workload}ai-${var.env}-${module.region_code.code}"
  search_sku          = "basic"

  storage_account_name       = "st${var.workload}srch${var.env}${module.region_code.code}"
  container_name             = "documents"
  soft_delete_retention_days = 2

  tags = merge(var.tags, { component = "ai-search" })
}

resource "azurerm_storage_account" "this" {
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
    delete_retention_policy {
      days = local.soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = local.soft_delete_retention_days
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = length(local.storage_account_name) <= 24
      error_message = "Storage account name ${local.storage_account_name} exceeds 24 chars. Shorten workload or env."
    }
  }
}

# ARM control plane, so the Terraform SP needs no data-plane grant; see
# modules/storage.
resource "azapi_resource" "documents_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = local.container_name
  parent_id = "${azurerm_storage_account.this.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azurerm_search_service" "this" {
  name                         = local.search_service_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  sku                          = local.search_sku
  local_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags

  depends_on = [
    azurerm_storage_account.this,
    azapi_resource.documents_container,
  ]
}

# Blob indexers read documents with the service's system identity.
resource "azurerm_role_assignment" "search_blob_reader" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_search_service.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "uami_index_reader" {
  scope                = azurerm_search_service.this.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = var.uami_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "uami_blob_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.uami_principal_id
  principal_type       = "ServicePrincipal"
}

locals {
  user_roles = var.search_user_object_id == null ? {} : {
    service_contributor = {
      scope = azurerm_search_service.this.id
      role  = "Search Service Contributor"
    }
    index_contributor = {
      scope = azurerm_search_service.this.id
      role  = "Search Index Data Contributor"
    }
    blob_contributor = {
      scope = azurerm_storage_account.this.id
      role  = "Storage Blob Data Contributor"
    }
  }
}

# Portal access for the signed-in user's Entra token.
resource "azurerm_role_assignment" "user" {
  for_each = local.user_roles

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = var.search_user_object_id
  principal_type       = "User"
}
