# envs/dev/08-service-bus/outputs.tf
# -----------------------------------------------------------------------------
# Re-exports the child module's outputs so downstream modules can read them
# via `data.terraform_remote_state`. Names MUST match what downstream
# modules request — do not rename without updating every consumer.
# -----------------------------------------------------------------------------

output "sb_namespace_id" {
  description = "Full Azure Resource ID of the Service Bus namespace."
  value       = module.service_bus.sb_namespace_id
}

output "sb_namespace_name" {
  description = "Namespace name (`sb-<env>-msg-<random>`). Used in the FQDN."
  value       = module.service_bus.sb_namespace_name
}

output "sb_namespace_fqdn" {
  description = "Fully-qualified namespace hostname (`<name>.servicebus.windows.net`). Passed to Container Apps as `SERVICEBUS_NAMESPACE_FQDN`."
  value       = module.service_bus.sb_namespace_fqdn
}

output "sb_namespace_endpoint" {
  description = "Endpoint URL exposed by the namespace resource (`sb://<name>.servicebus.windows.net/`)."
  value       = module.service_bus.sb_namespace_endpoint
}

output "sb_location" {
  description = "Azure region of the Service Bus namespace."
  value       = module.service_bus.sb_location
}

output "sb_sender_role_assignment_id" {
  description = "ID of the `Azure Service Bus Data Sender` role assignment granted to the shared UAMI at namespace scope."
  value       = module.service_bus.sb_sender_role_assignment_id
}

output "sb_receiver_role_assignment_id" {
  description = "ID of the `Azure Service Bus Data Receiver` role assignment granted to the shared UAMI at namespace scope."
  value       = module.service_bus.sb_receiver_role_assignment_id
}

output "sb_queue_names" {
  description = "Map from queue name → queue name. Empty when `queues = []`."
  value       = module.service_bus.sb_queue_names
}

output "sb_queue_ids" {
  description = "Map from queue name → full Azure Resource ID."
  value       = module.service_bus.sb_queue_ids
}
