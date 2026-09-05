# modules/log-analytics/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs, names, and keys for downstream callers.
#
# Terminology (Azure is confusing here):
#   - `id`           = Azure Resource ID (long "/subscriptions/.../workspaces/log-...")
#   - `workspace_id` = customer_id GUID that ingestion endpoints and CAE
#                      config both expect
#
# See docs/MODULES_DEPENDENCY.md for who consumes what.
# -----------------------------------------------------------------------------

output "law_id" {
  description = "Full Azure Resource ID of the workspace (`/subscriptions/.../workspaces/log-<env>-<random>`). Use for diagnostic settings, RBAC scoping."
  value       = azurerm_log_analytics_workspace.this.id
}

output "law_name" {
  description = "Workspace name (`log-<env>-<random>`)."
  value       = azurerm_log_analytics_workspace.this.name
}

output "law_workspace_id" {
  description = "Workspace customer_id GUID. Consumed by Container App Environment (module 10) and any tool that talks to the ingestion/query endpoints."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "law_primary_shared_key" {
  description = "Primary shared key. Legacy agent-auth path; the passwordless model does not use this, but downstream modules may need it for classic integrations (e.g. Container App Environment on some azurerm 4.x versions)."
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive   = true
}

output "law_location" {
  description = "Azure region of the workspace."
  value       = azurerm_log_analytics_workspace.this.location
}
