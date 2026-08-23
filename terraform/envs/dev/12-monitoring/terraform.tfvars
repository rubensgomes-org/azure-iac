# envs/dev/12-monitoring/terraform.tfvars
# -----------------------------------------------------------------------------
# Module-specific overrides for this root config. Loaded AFTER
# ../env.tfvars (which supplies env, location, tags), so any assignment
# here wins on conflict.
#
# The action group's email receiver is REQUIRED and only meaningful for
# this module — keep it here, not in the shared env.tfvars.
#
# See docs/PROVISIONING_PLAN.md §5 for the standard scaffolding across
# every module root.
# -----------------------------------------------------------------------------

# Email that receives alerts fired against the `owner` receiver on the
# `ag-dev-ops` action group. Playground default: the repo owner's
# personal address (also visible in userEmail context). Swap per env or
# per team as needed. Format is regex-validated in the child module.
action_group_email = "rubens.s.gomes@gmail.com"
