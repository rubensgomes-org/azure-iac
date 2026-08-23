# modules/service-bus/outputs.tf
# -----------------------------------------------------------------------------
# Publishes IDs and identifiers for downstream callers. Names MUST match
# what the plan (§4) commits to — do not rename without updating every
# consumer.
# -----------------------------------------------------------------------------

output "sb_namespace_id" {
  description = "Full Azure Resource ID of the Service Bus namespace. Use as `scope` for further role assignments outside this module."
  value       = azurerm_servicebus_namespace.this.id
}

output "sb_namespace_name" {
  description = "Namespace name (`sb-<env>-msg-<random>`). Used in the FQDN (`<name>.servicebus.windows.net`) — passed to Container Apps as `SERVICEBUS_NAMESPACE_FQDN`."
  value       = azurerm_servicebus_namespace.this.name
}

output "sb_namespace_fqdn" {
  description = "Fully-qualified namespace hostname (`<name>.servicebus.windows.net`). Apps connect here via `DefaultAzureCredential`."
  value       = "${azurerm_servicebus_namespace.this.name}.servicebus.windows.net"
}

output "sb_namespace_endpoint" {
  description = "Endpoint URL exposed by the namespace resource (`sb://<name>.servicebus.windows.net/`). Handy for parity with SDKs that want the full URI."
  value       = azurerm_servicebus_namespace.this.endpoint
}

output "sb_location" {
  description = "Azure region of the Service Bus namespace."
  value       = azurerm_servicebus_namespace.this.location
}

output "sb_sender_role_assignment_id" {
  description = "ID of the `Azure Service Bus Data Sender` role assignment granted to the shared UAMI at namespace scope."
  value       = azurerm_role_assignment.uami_sb_sender.id
}

output "sb_receiver_role_assignment_id" {
  description = "ID of the `Azure Service Bus Data Receiver` role assignment granted to the shared UAMI at namespace scope."
  value       = azurerm_role_assignment.uami_sb_receiver.id
}

output "sb_queue_names" {
  description = "Map from queue name → queue name. Consumed by module 11 to inject queue names into each app's env vars. Empty when `var.queues = []`."
  value       = { for k, q in azurerm_servicebus_queue.this : k => q.name }
}

output "sb_queue_ids" {
  description = "Map from queue name → full Azure Resource ID. Handy for future per-queue role assignments."
  value       = { for k, q in azurerm_servicebus_queue.this : k => q.id }
}
