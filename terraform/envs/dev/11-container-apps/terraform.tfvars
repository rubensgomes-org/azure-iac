# envs/dev/11-container-apps/terraform.tfvars
# -----------------------------------------------------------------------------
# Module-specific overrides for this root config. Loaded AFTER
# ../env.tfvars (which supplies env, apps, tags), so any assignment here
# wins on conflict.
#
# All values below are commented out: the child module ships defaults that
# work end-to-end with the `mcr.microsoft.com/k8se/quickstart:latest`
# placeholder (port 80, scale-to-zero, 0.25 vCPU / 0.5 GiB). Uncomment and
# adjust once real images exist in ACR.
#
# See docs/PROVISIONING_PLAN.md §5 for the standard scaffolding across
# every module root.
# -----------------------------------------------------------------------------

# ---- Real images (populate once pushed to ACR) -----------------------------
#
# Full image references, e.g.:
#   apps_image_map = {
#     api    = "acrdev1234.azurecr.io/api:1.2.3"
#     worker = "acrdev1234.azurecr.io/worker:1.2.3"
#   }
#
# Bump the tag to roll a new revision; `revision_mode = "Single"` means the
# new revision replaces the old on next apply.
#
# apps_image_map = {}

# ---- Target port -----------------------------------------------------------
#
# 80 = quickstart placeholder. 8080 = typical Spring Boot default. Must
# match the port the container inside the image actually listens on;
# ingress binds to this exact port.
#
# target_port = 8080

# ---- Resource shape --------------------------------------------------------
#
# 0.25 vCPU + 0.5 GiB is the Container Apps Consumption minimum — cheapest
# footprint for a playground. Valid pairs (partial list):
#   cpu = 0.25 → memory = "0.5Gi"
#   cpu = 0.5  → memory = "1Gi"
#   cpu = 1    → memory = "2Gi"
#   cpu = 2    → memory = "4Gi"
#
# cpu    = 0.5
# memory = "1Gi"

# ---- Scale rules -----------------------------------------------------------
#
# min_replicas = 0 puts apps to sleep after 5 minutes of no traffic. Set
# to 1 for latency-sensitive apps (no cold-start penalty).
# max_replicas = 1 disables horizontal scale-out until a scale rule is
# added to the child module.
#
# min_replicas = 1
# max_replicas = 3

# ---- Ingress ---------------------------------------------------------------
#
# true = public FQDN per app on the environment's static IP.
# false = ingress internal to the environment (needs a VNet-reachable
# client to hit the apps).
#
# ingress_external_enabled = true
