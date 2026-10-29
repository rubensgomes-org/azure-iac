# modules/foundry/main.tf
# -----------------------------------------------------------------------------
# Provisions an Azure AI Foundry resource (`kind = AIServices`), one project
# under it, a "Cognitive Services OpenAI User" grant for the shared UAMI, an
# optional "Foundry User" grant for a human user, and an optional Application
# Insights connected to the resource for agent tracing.
#
# Design decisions (fixed here, not variables):
#
# * **S0 SKU.** Standard tier; usage is billed per model call.
#
# * **Custom subdomain = resource name.** Required for Entra ID auth and for
#   projects. The subdomain is globally unique and held by a soft-deleted
#   resource until purged; the calling root purges on destroy.
#
# * **Role by ID, not name.** "Foundry User" was renamed from "Azure AI User";
#   the role definition ID survives renames.
#
# * **UAMI gets "Cognitive Services OpenAI User", not "Foundry User".** It
#   covers model inference (including the Responses API) without granting
#   every `Microsoft.CognitiveServices/*` data action.
# -----------------------------------------------------------------------------

locals {
  # Azure accepts "Sweden Central" as well as "swedencentral".
  region            = lower(replace(var.location, " ", ""))
  account_name      = "aif-${var.workload}-${var.env}-${local.region}"
  project_name      = "proj-${var.workload}-${var.env}-${local.region}"
  app_insights_name = "appi-${var.workload}ai-${var.env}"

  kind     = "AIServices"
  sku_name = "S0"

  foundry_user_role_id = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
  openai_user_role_id  = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd"
}

data "azurerm_client_config" "current" {}

resource "azurerm_cognitive_account" "this" {
  name                       = local.account_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  kind                       = local.kind
  sku_name                   = local.sku_name
  custom_subdomain_name      = local.account_name
  project_management_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = merge(
    var.tags,
    { component = "foundry" },
  )
}

resource "azurerm_cognitive_account_project" "this" {
  name                 = local.project_name
  cognitive_account_id = azurerm_cognitive_account.this.id
  location             = var.location

  identity {
    type = "SystemAssigned"
  }

  tags = merge(
    var.tags,
    { component = "foundry" },
  )
}

resource "azurerm_role_assignment" "foundry_user" {
  count = var.foundry_user_object_id == null ? 0 : 1

  scope              = azurerm_cognitive_account.this.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.foundry_user_role_id}"
  principal_id       = var.foundry_user_object_id
  principal_type     = "User"
}

resource "azurerm_role_assignment" "uami_openai_user" {
  scope              = azurerm_cognitive_account.this.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.openai_user_role_id}"
  principal_id       = var.uami_principal_id
  principal_type     = "ServicePrincipal"
}

# Foundry agent tracing exports OpenTelemetry to the Application Insights
# behind this connection.
resource "azurerm_application_insights" "this" {
  count = var.app_insights_enabled ? 1 : 0

  name                = local.app_insights_name
  location            = var.location
  resource_group_name = var.resource_group_name

  workspace_id     = var.log_analytics_workspace_id
  application_type = "web"

  tags = merge(
    var.tags,
    { component = "foundry" },
  )
}

resource "azurerm_cognitive_account_connection_api_key" "app_insights" {
  count = var.app_insights_enabled ? 1 : 0

  name                 = local.app_insights_name
  cognitive_account_id = azurerm_cognitive_account.this.id
  category             = "AppInsights"
  target               = azurerm_application_insights.this[0].id
  api_key              = azurerm_application_insights.this[0].connection_string

  metadata = {
    ApiType    = "Azure"
    ResourceId = azurerm_application_insights.this[0].id
  }
}
