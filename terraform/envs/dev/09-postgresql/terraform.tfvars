# envs/dev/09-postgresql/terraform.tfvars
# -----------------------------------------------------------------------------
# Module-specific overrides for this root config. Loaded AFTER ../env.tfvars
# (which supplies env, location, apps, pg_entra_admin_group_object_id, tags),
# so any assignment here wins on conflict.
#
# Server SKU (`B_Standard_B1ms`), engine version (`16`), storage size,
# backup retention, and network posture are hard-coded in the child
# module (`modules/postgresql/main.tf`). Change there if you need a
# bigger tier, HA, or the eventual VNet-only migration.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Region override — PG Flex only
# -----------------------------------------------------------------------------
# The shared env.tfvars pins the estate to `eastus`, but this subscription
# is offer-restricted from provisioning PostgreSQL Flexible Server there:
#
#   Status:  LocationIsOfferRestricted
#   Message: Subscriptions are restricted from provisioning in location
#            'eastus'. Try again in a different location.
#            See https://aka.ms/postgres-request-quota-increase
#
# Restriction is per-subscription + per-service (PG Flex only) — every
# other module (RGs, VNet, KV, ACR, Storage, Service Bus) provisions to
# `eastus` without issue. Cheapest workaround: land PG Flex in the nearest
# unrestricted region. `eastus2` is geographically adjacent (~2-5 ms
# runtime latency to Container Apps in eastus, negligible for a
# playground).
#
# The parent RG `rg-dev-data` stays in `eastus`; Azure allows an RG to
# hold resources in a different region. `var.location` is consumed by
# the server, firewall rules, and per-app databases in the child module,
# so setting it here moves ALL PG resources in one go.
#
# Revisit if:
#   - Microsoft lifts the restriction (unlikely for playground subs).
#   - A quota exception is granted via the aka.ms link above.
#   - You migrate the estate off `eastus` — then move this back to the
#     shared env.tfvars value.
location = "eastus2"
