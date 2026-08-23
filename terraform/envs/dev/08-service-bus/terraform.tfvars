# envs/dev/08-service-bus/terraform.tfvars
# -----------------------------------------------------------------------------
# Module-specific overrides for this root config. Loaded AFTER ../env.tfvars
# (which supplies env, location, prefix, apps, tags), so any assignment here
# wins on conflict.
#
# `queues` is a service-bus concern (queue topology is between apps, not
# per-app), so it lives here rather than in the shared env.tfvars. Empty
# list = the namespace and RBAC are still provisioned; add queue names
# below when the apps need message channels.
#
# Example:
#   queues = ["events", "orders"]
# -----------------------------------------------------------------------------

queues = []
