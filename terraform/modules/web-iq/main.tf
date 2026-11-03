# modules/web-iq/main.tf
# -----------------------------------------------------------------------------
# Provisions a Microsoft Web IQ account (`Microsoft.WebIQ/accounts`), which
# has no azurerm resource.
#
# Design decisions (fixed here, not variables):
#
# * **Global.** The account location is always `global`, so the name has no
#   region suffix.
#
# * **No RBAC.** Web IQ authorizes callers per AppID, bound in the Web IQ
#   portal, not through Azure role assignments.
#
# * **No schema validation.** The preview API version may be missing from
#   the azapi provider's embedded schema.
# -----------------------------------------------------------------------------

locals {
  account_name = "wiq-${var.workload}ai-${var.env}"

  resource_type = "Microsoft.WebIQ/accounts@2026-06-01-preview"
  location      = "global"
  kind          = "WebIQ.Grounding"
  sku_name      = "G3"
}

resource "azapi_resource" "this" {
  type      = local.resource_type
  name      = local.account_name
  location  = local.location
  parent_id = var.resource_group_id

  schema_validation_enabled = false

  body = {
    kind = local.kind
    sku = {
      name = local.sku_name
    }
    properties = {
      statisticsEnabled = false
    }
  }

  tags = merge(
    var.tags,
    { component = "web-iq" },
  )
}
