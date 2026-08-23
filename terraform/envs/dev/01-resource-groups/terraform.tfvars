# envs/dev/01-resource-groups/terraform.tfvars
# -----------------------------------------------------------------------------
# Module-specific overrides for this root config. Loaded AFTER ../env.tfvars
# (which supplies env, location, prefix, apps, tags), so any assignment here
# wins on conflict.
#
# resource-groups is fully driven by the shared env.tfvars — this file is
# intentionally empty. Kept in place for scaffolding consistency across every
# module root (see docs/PROVISIONING_PLAN.md §5).
# -----------------------------------------------------------------------------
