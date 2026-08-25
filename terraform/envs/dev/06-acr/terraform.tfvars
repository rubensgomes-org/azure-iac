# envs/dev/06-acr/terraform.tfvars
# -----------------------------------------------------------------------------
# Module-specific overrides for this root config. Loaded AFTER ../env.tfvars
# (which supplies env, location, prefix, apps, tags), so any assignment here
# wins on conflict.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Registry name
# -----------------------------------------------------------------------------
# Explicit, fixed, and deliberately NOT derived from `env` or suffixed with a
# random value the way kv-/st-/sb-/log-/psql- names are. Rationale in
# modules/acr/main.tf: this is the one name that gets typed constantly — it is
# baked into every image tag, `docker push`, `az acr` call, and (later)
# `apps_image_map` entry — so it must be memorable AND stable across a
# destroy+recreate.
#
# It lives here rather than in ../env.tfvars because env.tfvars is shared by
# all twelve module roots; a registry name is a single module's concern.
#
# CONSTRAINTS (enforced by validation on var.acr_name in modules/acr):
#   - 5-50 characters
#   - alphanumeric ONLY — no dashes, no underscores
#   - globally unique across every Azure tenant, not just this subscription
#
# Confirmed available before being set here. Re-check before changing it, or
# before adding this pattern to a new environment:
#
#   az acr check-name -n rubensdevacr
#   # => { "nameAvailable": true, "reason": null, "message": null }
#
# CHANGING THIS VALUE RENAMES THE REGISTRY, which azurerm implements as
# destroy-and-recreate: every image in the old registry is lost and every
# reference to the old login server breaks. Treat an edit here as a MAJOR
# version bump per RELEASING.md.
acr_name = "rubensdevacr"
