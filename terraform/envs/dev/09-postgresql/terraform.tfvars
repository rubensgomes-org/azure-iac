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
# Region — NO override (removed in v0.4.2)
# -----------------------------------------------------------------------------
# PG Flex now inherits `location` from the shared ../env.tfvars along with every
# other module. There is deliberately no `location =` line in this file.
#
# History, so the absence does not read as an accident: this subscription is
# offer-restricted from provisioning PostgreSQL Flexible Server in `eastus` —
#
#   Status:  LocationIsOfferRestricted
#   Message: Subscriptions are restricted from provisioning in location
#            'eastus'. Try again in a different location.
#            See https://aka.ms/postgres-request-quota-increase
#
# — so while the estate lived in `eastus` this file pinned PG to `eastus2`. The
# restriction is per-subscription AND per-service: it hit PG Flex only, never the
# RGs, VNet, KV, ACR, Storage, or Service Bus. Moving the estate to `centralus`
# was exactly the exit condition that override documented, because `centralus` is
# NOT restricted. Verified before the move:
#
#   az postgres flexible-server list-skus --location centralus
#     -> no restriction; Standard_B1ms available, zones [1,2,3], 32768 MB
#     (compare `--location eastus`, which still reports the restriction above)
#
# If you point env.tfvars at a new region, re-run that command FIRST. If the new
# region is restricted, reinstate a `location = "<nearest-unrestricted>"` line
# here — `var.location` is consumed by the server, its firewall rules, and every
# per-app database in the child module, so one line moves all PG resources
# together. The parent RG `rg-dev-data` follows env.tfvars either way; Azure
# permits an RG to hold resources from another region.
# -----------------------------------------------------------------------------
