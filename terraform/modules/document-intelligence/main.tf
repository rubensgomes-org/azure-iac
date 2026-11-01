# modules/document-intelligence/main.tf
# -----------------------------------------------------------------------------
# Provisions an Azure AI Document Intelligence resource (`kind =
# FormRecognizer`) and a "Cognitive Services User" grant for the shared UAMI.
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
