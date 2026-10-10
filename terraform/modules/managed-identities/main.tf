# modules/managed-identities/main.tf
# -----------------------------------------------------------------------------
# Provisions the SINGLE shared User-Assigned Managed Identity used by every
# microservice in the ACA environment.
#
# One identity, one blast-radius, minimal RBAC ceremony:
#   - Attached to every azurerm_container_app in module 12
#   - Granted `App Configuration Data Reader` on the store (module 05)
#   - Granted `Key Vault Secrets User` on the vault (module 06)
#   - Granted `AcrPull` on ACR (module 07)
#   - Granted `Storage Blob Data Contributor` on the storage account (module 08)
#   - Granted Service Bus `Data Sender` / `Data Receiver` (module 09)
#   - Registered as an in-DB AAD principal on every PG database (module 10)
#
# Per-app identities are explicitly OUT OF SCOPE for this playground. See
# the module README for the trade-off (uniform blast-radius vs. per-app
# RBAC granularity).
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "app" {
  # CAF form `id-<workload>-<env>` with the `app` purpose folded onto the
  # workload token, matching the rest of the estate: id-rgomesapp-lab.
  name                = "id-${var.workload}app-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(
    var.tags,
    { component = "managed-identity" },
  )
}
