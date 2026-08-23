# modules/managed-identities/main.tf
# -----------------------------------------------------------------------------
# Provisions the SINGLE shared User-Assigned Managed Identity used by every
# microservice in the ACA environment.
#
# One identity, one blast-radius, minimal RBAC ceremony:
#   - Attached to every azurerm_container_app in module 11
#   - Granted `Key Vault Secrets User` on the vault (module 05)
#   - Granted `AcrPull` on ACR (module 06)
#   - Granted `Storage Blob Data Contributor` on the storage account (module 07)
#   - Granted Service Bus `Data Sender` / `Data Receiver` (module 08)
#   - Registered as an in-DB AAD principal on every PG database (module 09)
#
# Per-app identities are explicitly OUT OF SCOPE for this playground. See
# docs/PROVISIONING_PLAN.md §12 for the trade-off (uniform blast-radius vs.
# per-app RBAC granularity).
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.env}-app"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(
    var.tags,
    { component = "managed-identity" },
  )
}
