# modules/foundry-project/main.tf
# -----------------------------------------------------------------------------
# Provisions one project under an existing Azure AI Foundry resource
# (modules/foundry-resource). The project's managed identity gets no roles here.
# -----------------------------------------------------------------------------

module "region_code" {
  source   = "../region-code"
  location = var.location
}

locals {
  project_name = "proj-${var.workload}ai${var.name_suffix}-${var.env}-${module.region_code.code}"
}

resource "azurerm_cognitive_account_project" "this" {
  name                 = local.project_name
  cognitive_account_id = var.foundry_id
  location             = var.location

  identity {
    type = "SystemAssigned"
  }

  tags = merge(
    var.tags,
    { component = "foundry" },
  )
}
