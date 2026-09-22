# Root Makefile — dev-estate automation.
# -----------------------------------------------------------------------------
# Wraps the per-module `terraform init/plan/apply/destroy` invocations that
# every module README documents by hand. Nothing in here is magic — every
# recipe just chdirs into the module's root and runs the exact commands that
# already work when you type them yourself. The point is convenience and
# ordering:
#
#   * Per-module targets (init-/plan-/apply-/destroy-<name>) let you drive
#     one module at a time without remembering the numeric prefix or the
#     backend-config incantation. `<name>` is the short suffix — `key-vault`,
#     not `05-key-vault`.
#
#   * Whole-estate targets iterate the modules in the correct order (01→12
#     for apply, 12→01 for destroy). Both are shell blocks lifted in
#     verbatim, so the Makefile stays honest to the plan.
#
#   * `destroy` also runs the post-destroy Key Vault purge (dev toggle,
#     purge_protection = false) and reports any soft-deleted PG server
#     still holding the name. Same block as `destroy`.
#
# Design decisions worth calling out:
#
#   * All targets are .PHONY. Terraform manages its own change detection —
#     Make just orchestrates. Trying to teach Make about `.tfstate` freshness
#     would only invent bugs.
#
#   * Recipes use `set -e` and shell `for` loops instead of Make-level
#     prereq chains, so behaviour under `make -jN` is deterministic
#     (strictly serial). Terraform apply order across modules is a hard
#     requirement — parallelising it would break remote-state reads.
#
#   * `apply-<name>` uses `-auto-approve`; whole-estate `apply` does too.
#     For safe review, run `plan-<name>` first.
#
#   * `terraform init -reconfigure` on every invocation. Cheap (cached
#     provider plugins), and immune to the "backend key drifted" class of
#     bug that ate an afternoon during the 05/07 state-corruption incident.
#
# Assumes ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID /
# ARM_SUBSCRIPTION_ID are exported in the shell. See docs/INITIAL_SETUP.md.
# -----------------------------------------------------------------------------

ENV     ?= dev

# The two halves of the layout, and the whole point of the split:
#
#   ROOTS_DIR  the twelve module roots. ONE copy, shared by every environment.
#              Nothing in here names an environment -- `var.env` carries it.
#   ENV_DIR    per-environment configuration ONLY: backend.hcl, tags.json and
#              the gitignored env.tfvars. Three files, not 4,350 lines.
#
# Every terraform invocation below therefore runs in ROOTS_DIR and is pointed
# at ENV_DIR by flags. Paths inside a recipe are relative to the root it cd'd
# into, which is why they read `../../envs/$(ENV)/...` rather than $(ENV_DIR).
ROOTS_DIR := terraform/roots
ENV_DIR   := terraform/envs/$(ENV)

# Variable-file flag, or nothing when the file is absent.
#
# `env.tfvars` sits in ENV_DIR, outside the directory terraform runs in, so it
# needs an explicit flag. (An auto-loaded `terraform.tfvars` would need none --
# which is exactly why check-tfvars below refuses one inside a shared root.)
# env.tfvars is gitignored (.gitignore: *.tfvars) and therefore absent on a CI
# runner, where the same values arrive as TF_VAR_* environment variables
# instead. Naming a -var-file that does not exist is a hard error ("Failed to
# read variables file"), which is exactly what used to break the workflows, so
# gate the flag on existence.
#
# `:=` and $(wildcard) both resolve at parse time against ENV_DIR, which is
# already fixed by then. A missing file plus a missing TF_VAR_ export still
# fails, but with Terraform's own "No value for required variable" -- which
# names the variable, unlike the old error.
#
# The existence test is repo-relative (Make's cwd); the flag it emits is
# root-relative (terraform's cwd after the cd). Those are two different
# directories and the mismatch is deliberate, not a bug.
ENV_VARFILE := $(if $(wildcard $(ENV_DIR)/env.tfvars),-var-file=../../envs/$(ENV)/env.tfvars,)

# Backend coordinate overrides for `terraform init`.
#
# ENV_DIR's backend.hcl is committed and is the local default. Terraform merges
# repeated -backend-config in order and the last one wins, so appending these
# lets CI (or a second lab subscription) retarget the state account without
# editing a tracked file. Unset variables expand to nothing and backend.hcl
# stands alone.
#
# These MUST stay in step with the like-named Terraform variables the module
# roots declare for their `data "terraform_remote_state"` reads -- this pair
# points at the same storage account from the two places Terraform keeps
# separate: `init` for our own state, `var.*` for everyone else's.
BACKEND_OVERRIDES := \
  $(if $(TF_VAR_backend_resource_group_name),-backend-config="resource_group_name=$(TF_VAR_backend_resource_group_name)") \
  $(if $(TF_VAR_storage_account_id),-backend-config="storage_account_name=$(TF_VAR_storage_account_id)") \
  $(if $(TF_VAR_container_name),-backend-config="container_name=$(TF_VAR_container_name)")

# CAF workload token, mirroring the `workload` input every module takes.
# Terraform reads TF_VAR_workload from the environment; Make imports the
# environment as variables, so the same export reaches both without a second
# knob.
#
# Unset or empty falls back to `rgomes`, which is every module's declared
# default for `workload`. The two MUST agree: if this line fell back to
# something else while Terraform named the RG `rg-rgomesobservability-lab`, the
# sweep below would query an RG that does not exist, report "(none)" through
# its `|| true`, and module 01's destroy would then fail on
# `prevent_deletion_if_contains_resources` naming none of this.
#
# The trap worth knowing: unlike the backend coordinates, `workload` DOES live
# in ../../envs/<env>/env.tfvars, and `-var-file` outranks `TF_VAR_*`. So
# exporting TF_VAR_workload changes what this line builds without changing what
# Terraform names. Set it in env.tfvars and leave the export alone, or set both.
#
# This exists solely so the orphan sweep below can name the observability RG.
# Nothing else in this Makefile constructs an RG name; every terraform target
# passes -var-file and lets Terraform do it.
WORKLOAD := $(if $(TF_VAR_workload),$(TF_VAR_workload),rgomes)

# Release version. The repo-root VERSION file is the single source of truth:
# the git tag is `v$(VERSION)`, the CHANGELOG heading is `[$(VERSION)]`, and
# every module root reads the same file to stamp a `release` tag onto every
# Azure resource.
#
# Read with `:=` (once, at parse time) rather than `=`, so a recipe that
# rewrites VERSION mid-flight still sees the value the target STARTED with.
# The bump recipes therefore re-read the file in-shell rather than using
# $(VERSION); the variable here is for reporting and for `release-push`.
VERSION     := $(shell cat VERSION 2>/dev/null)
RELEASE_TAG := v$(VERSION)

# Modules in dependency (apply) order. Directory prefix `NN-` encodes ordering
# and is also the source of truth for `NAMES` (used to derive backend keys).
# Add a new module here and per-module targets appear automatically via
# MODULE_TARGETS below.
DIRS := \
  01-resource-groups \
  02-networking \
  03-log-analytics \
  04-managed-identities \
  05-key-vault \
  06-acr \
  07-storage \
  08-service-bus \
  09-postgresql \
  10-container-app-environment \
  11-container-apps \
  12-monitoring

# Destroy order is the strict reverse of DIRS. Reversing is
# done in Make rather than the shell because `tac` is a GNU coreutils tool and
# does NOT exist on macOS/BSD — the original `... | tac` silently produced an
# EMPTY list there, the destroy loop iterated zero times, and `make destroy`
# went straight to the Key Vault purge having torn down nothing. `set -e`
# cannot catch that: the failure happens inside a command substitution used as
# a `for` word-list, so the loop's own exit status stays 0.
#
# This recursive-reverse idiom is pure Make (no external tools, portable
# everywhere) and keeps DIRS as the single source of truth, so adding a module
# cannot leave the destroy order stale.
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)))
DIRS_REV := $(strip $(call reverse,$(DIRS)))

# Default target — `make` with no args shows usage. Keep this the first target.
.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
# Per-module target factory
# -----------------------------------------------------------------------------
# For each DIRS entry, generate init-/plan-/apply-/destroy-<short-name>.
# Backend key is the short name (`key-vault/terraform.tfstate`), matching
# what every module README documents.
define MODULE_TARGETS
.PHONY: init-$(2) plan-$(2) plan-destroy-$(2) apply-$(2) destroy-$(2)

init-$(2): check-backend
	@echo "=== INIT $(1) ==="
	@cd $(ROOTS_DIR)/$(1) && terraform init -reconfigure \
	  -backend-config=../../envs/$(ENV)/backend.hcl \
	  -backend-config="key=$(2)/terraform.tfstate" \
	  $(BACKEND_OVERRIDES)

plan-$(2): init-$(2)
	@echo "=== PLAN $(1) ==="
	@cd $(ROOTS_DIR)/$(1) && terraform plan \
	  $(ENV_VARFILE) -out=tfplan

# Speculative TEARDOWN plan. Writes the same `tfplan` filename as plan-$(2),
# so the two overwrite each other — that is deliberate: a stale plan file of
# the wrong polarity is far more dangerous than no plan file at all. Nothing
# consumes the artifact (destroy-$(2) re-plans internally under
# -auto-approve); it exists to be READ, by eye or by `terraform show -json`.
plan-destroy-$(2): init-$(2)
	@echo "=== PLAN -destroy $(1) ==="
	@cd $(ROOTS_DIR)/$(1) && terraform plan -destroy \
	  $(ENV_VARFILE) -out=tfplan

apply-$(2): init-$(2)
	@echo "=== APPLY $(1) ==="
	@cd $(ROOTS_DIR)/$(1) && terraform apply -auto-approve \
	  $(ENV_VARFILE)

destroy-$(2): init-$(2)
	@echo "=== DESTROY $(1) ==="
	@cd $(ROOTS_DIR)/$(1) && terraform destroy -auto-approve \
	  $(ENV_VARFILE)
endef

$(eval $(call MODULE_TARGETS,01-resource-groups,resource-groups))
$(eval $(call MODULE_TARGETS,02-networking,networking))
$(eval $(call MODULE_TARGETS,03-log-analytics,log-analytics))
$(eval $(call MODULE_TARGETS,04-managed-identities,managed-identities))
$(eval $(call MODULE_TARGETS,05-key-vault,key-vault))
$(eval $(call MODULE_TARGETS,06-acr,acr))
$(eval $(call MODULE_TARGETS,07-storage,storage))
$(eval $(call MODULE_TARGETS,08-service-bus,service-bus))
$(eval $(call MODULE_TARGETS,09-postgresql,postgresql))
$(eval $(call MODULE_TARGETS,10-container-app-environment,container-app-environment))
# 11-container-apps is deliberately NOT generated here. Its plan/apply/
# destroy targets are hand-written below, scoped to TF_VAR_apps. See the
# "Container Apps" section.
$(eval $(call MODULE_TARGETS,12-monitoring,monitoring))

# -----------------------------------------------------------------------------
# Container Apps (module 11) — targets scoped to TF_VAR_apps
# -----------------------------------------------------------------------------
# Module 11 is the one root whose resources are keyed by a variable:
# `azurerm_container_app.app` is `for_each = toset(var.apps)`. Every other
# module owns a fixed set of resources, so the generic MODULE_TARGETS
# recipes are right for them and wrong here.
#
# Wrong in BOTH directions, and neither announces itself:
#
#   * apply. Each app's own repository calls the reusable aca-create
#     workflow passing only ITS app, so var.apps is a per-caller value
#     rather than the estate's full list. An unscoped
#     `terraform apply -auto-approve` reconciles the whole for_each map,
#     so `TF_VAR_apps='["mathmcp"]'` plans `app["mathmcp"] will be
#     created` AND `app["nettools"] will be destroyed (because key
#     ["nettools"] is not in for_each map)`. A create in one repo deletes
#     every other repo's app.
#
#   * destroy. `terraform destroy` ignores var.apps entirely and tears
#     down every instance in state, so naming one app destroys them all.
#
# Both recipes below therefore pass one -target per app in TF_VAR_apps.
# The whole-estate `apply` loop is guarded separately (see
# ASSERT_APPS_COVER_STATE); the whole-estate `destroy` loop is NOT, and
# deliberately so -- see its comment.

# Validates TF_VAR_apps and builds the `targets` shell variable of
# -target flags. Inlined into the recipes below, same as SWEEP_ORPHANS.
#
# The name charset check is load-bearing, not cosmetic. TF_VAR_apps can
# arrive from a repository variable edited in the GitHub UI with no review
# and no diff, and `$$targets` is expanded UNQUOTED by the recipes (it has
# to be, to word-split into separate flags). A name such as
# `x -auto-approve` would otherwise smuggle an argument into terraform.
#
# The jq program is kept on ONE physical line, for the same reason every
# awk program in this file is: a `\`-continuation inside a single-quoted
# program reaches jq literally, backslash and all, and fails to parse.
define CONTAINER_APPS_TARGET_FLAGS
if ! printf '%s' "$$TF_VAR_apps" \
     | jq -e 'type=="array" and length>0 and all(.[];test("^[a-z][a-z0-9-]*$$"))' \
       >/dev/null 2>&1; then \
  echo "ERROR: TF_VAR_apps must be a non-empty JSON array of app names," >&2; \
  echo "  lowercase letters/digits/hyphens, starting with a letter." >&2; \
  echo "  e.g. TF_VAR_apps='[\"nettools\"]'" >&2; \
  echo "  Got: '$$TF_VAR_apps'" >&2; \
  exit 1; \
fi; \
_addr="module.container_apps.azurerm_container_app.app"; \
targets=""; \
for _app in $$(printf '%s' "$$TF_VAR_apps" | jq -r '.[]'); do \
  targets="$$targets -target=$$_addr[\"$$_app\"]"; \
done; \
echo "  apps in scope: $$TF_VAR_apps"
endef

# Refuses an UNSCOPED apply that would destroy an app nobody asked about.
# Used by the whole-estate `apply` loop, which runs terraform inline
# rather than through apply-container-apps and so carries no -target.
define ASSERT_APPS_COVER_STATE
echo "=== GUARD module 11: TF_VAR_apps must cover state ==="; \
_want=" $$(printf '%s' "$$TF_VAR_apps" | jq -r '.[]' 2>/dev/null \
           | tr '\n' ' ')"; \
_have=$$( cd $(ROOTS_DIR)/11-container-apps \
          && terraform state list 2>/dev/null \
          | sed -n 's/.*azurerm_container_app\.app\["\(.*\)"\]$$/\1/p' ); \
_extra=""; \
for _app in $$_have; do \
  case "$$_want" in *" $$_app "*) ;; *) _extra="$$_extra $$_app";; esac; \
done; \
if [ -n "$$_extra" ]; then \
  echo "ERROR: module 11's state holds app(s) absent from TF_VAR_apps:" >&2; \
  echo "ERROR:$$_extra" >&2; \
  echo "  A whole-estate apply reconciles the whole for_each map, so it" >&2; \
  echo "  would DESTROY the app(s) above. TF_VAR_apps must name every" >&2; \
  echo "  app this environment should have, not just the one you are" >&2; \
  echo "  adding. To act on a single app, use apply-container-apps," >&2; \
  echo "  which scopes to TF_VAR_apps with -target." >&2; \
  exit 1; \
fi; \
echo "  ok: TF_VAR_apps covers every app in state"
endef

.PHONY: init-container-apps plan-container-apps plan-destroy-container-apps
.PHONY: apply-container-apps destroy-container-apps

init-container-apps: check-backend
	@echo "=== INIT 11-container-apps ==="
	@cd $(ROOTS_DIR)/11-container-apps && terraform init -reconfigure \
	  -backend-config=../../envs/$(ENV)/backend.hcl \
	  -backend-config="key=container-apps/terraform.tfstate" \
	  $(BACKEND_OVERRIDES)

# `set -f` on every recipe below is load-bearing. Recipes run under
# /bin/sh (this Makefile sets no SHELL), so bash arrays are unavailable
# and `$$targets` MUST expand unquoted to word-split into separate flags
# -- which leaves the `[` and `]` in each resource address exposed to
# pathname expansion. `set -f` turns globbing off for the rest of the
# recipe. Do NOT "fix" this by quoting `$$targets`: that hands terraform
# every flag as one argument.
plan-container-apps: init-container-apps
	@echo "=== PLAN 11-container-apps ==="
	@set -f; $(CONTAINER_APPS_TARGET_FLAGS); \
	 cd $(ROOTS_DIR)/11-container-apps && terraform plan \
	   $(ENV_VARFILE) $$targets -out=tfplan

# Speculative TEARDOWN plan; same tfplan-overwrite rationale as the
# generic plan-destroy-<name> recipe in MODULE_TARGETS.
plan-destroy-container-apps: init-container-apps
	@echo "=== PLAN -destroy 11-container-apps ==="
	@set -f; $(CONTAINER_APPS_TARGET_FLAGS); \
	 cd $(ROOTS_DIR)/11-container-apps && terraform plan -destroy \
	   $(ENV_VARFILE) $$targets -out=tfplan

apply-container-apps: init-container-apps
	@echo "=== APPLY 11-container-apps ==="
	@set -f; $(CONTAINER_APPS_TARGET_FLAGS); \
	 cd $(ROOTS_DIR)/11-container-apps && terraform apply -auto-approve \
	   $(ENV_VARFILE) $$targets

destroy-container-apps: init-container-apps
	@echo "=== DESTROY 11-container-apps ==="
	@set -f; $(CONTAINER_APPS_TARGET_FLAGS); \
	 cd $(ROOTS_DIR)/11-container-apps && terraform destroy -auto-approve \
	   $(ENV_VARFILE) $$targets

# -----------------------------------------------------------------------------
# Whole-estate: apply (01 → 12)
# -----------------------------------------------------------------------------
# Kept in a shell for-loop so ordering is strictly serial regardless of
# `make -jN`.
#
# init and apply are two separate subshells, not one `&&` chain, so the
# module 11 guard can read that module's state in between. The guard
# needs an initialised module, and it must run before the apply it is
# protecting against -- there is no third place to put it.
.PHONY: apply
apply: check-backend
	@set -e; for d in $(DIRS); do \
	  key="$${d#[0-9][0-9]-}"; \
	  echo "=== APPLY $$d ==="; \
	  ( cd $(ROOTS_DIR)/$$d \
	    && terraform init -reconfigure \
	         -backend-config=../../envs/$(ENV)/backend.hcl \
	         -backend-config="key=$$key/terraform.tfstate" \
	         $(BACKEND_OVERRIDES) ); \
	  if [ "$$d" = "11-container-apps" ]; then \
	    $(ASSERT_APPS_COVER_STATE); \
	  fi; \
	  ( cd $(ROOTS_DIR)/$$d \
	    && terraform apply -auto-approve \
	         $(ENV_VARFILE) ); \
	done

# -----------------------------------------------------------------------------
# Orphan sweep — Azure-generated resources Terraform never owned
# -----------------------------------------------------------------------------
# Creating an Application Insights component makes Azure ALSO create an action
# group named "Application Insights Smart Detection" in the same RG. Terraform
# never manages it, so destroying module 12 leaves it behind — and then module
# 01 cannot delete rg-<env>-observability, because azurerm's
# `prevent_deletion_if_contains_resources` (default true) refuses to delete an
# RG with unknown resources in it. This recurs on EVERY teardown.
#
# The sweep runs between module 02 and module 01 (see the destroy loop), by
# which point every Terraform-managed resource in these RGs is already gone —
# so anything still standing is by definition an orphan, in an RG that is about
# to be deleted regardless.
#
# `--ids` rather than `-g/-n`: the action group's name contains SPACES, and
# `az ... -n Application Insights Smart Detection` parses the words as separate
# positional args and dies with "unrecognized arguments". Reading IDs via
# `while IFS= read -r` keeps them intact.
# The sweep body lives in a variable, NOT a target invoked via $(MAKE), so that
# the destroy recipe can inline it. Recursive $(MAKE) inside a recipe is a trap
# here: GNU Make executes any recipe line containing $(MAKE) even under `-n`,
# and because the destroy recipe is one backslash-continued logical line, a
# `make -n destroy` would run the ENTIRE teardown for real instead of printing
# it. Inlining keeps `-n` an honest dry run.
define SWEEP_ORPHANS
echo "=== SWEEP Azure-generated orphans (rg-$(WORKLOAD)observability-$(ENV)) ==="; \
ids=$$(az monitor action-group list -g rg-$(WORKLOAD)observability-$(ENV) \
         --query "[].id" -o tsv 2>/dev/null || true); \
if [ -z "$$ids" ]; then echo "  (none)"; else \
  echo "$$ids" | while IFS= read -r id; do \
    [ -n "$$id" ] || continue; \
    echo "  deleting $$id"; \
    az monitor action-group delete --ids "$$id" || true; \
  done; \
fi
endef

.PHONY: purge-orphans
purge-orphans:
	@$(SWEEP_ORPHANS)

# -----------------------------------------------------------------------------
# Whole-estate: destroy (12 → 01) + post-destroy Key Vault check
# -----------------------------------------------------------------------------
# KV_NAME is captured BEFORE the loop, because module 05's state gets emptied
# by its own destroy step. The capture re-inits against the REAL backend first:
# without that, a preceding `make validate` (which inits with `-backend=false`)
# leaves `.terraform/` pointing at an empty local backend, `terraform output`
# fails, `|| true` swallows it, and the check below is silently skipped.
#
# The Key Vault step VERIFIES rather than blindly purges. Module 05's provider
# uses `features {}`, so `key_vault.purge_soft_delete_on_destroy` takes its
# default of TRUE — the provider already purges the vault during destroy. An
# unconditional `az keyvault purge` therefore fails with
# `(DeletedVaultNotFound) ... does not exist`, which reads like a teardown
# failure but means the opposite. So: look for a soft-deleted vault, purge only
# if one is actually there.
#
# That step is load-bearing since the CAF rename. Names carry no random suffix
# any more, so a vault left soft-deleted blocks the one and only name the next
# apply will ask for. The same is true of the Log Analytics workspace, which
# has NO equivalent step here because the provider does not purge it and
# `az monitor log-analytics workspace` offers no list-deleted: recreating
# inside its 14-day window either recovers the old workspace or fails, and
# `--force` on the delete is the way out. docs/TEARDOWN.md carries the
# procedure.
#
# There is deliberately NO PostgreSQL step. `az postgres flexible-server list
# --show-deleted` does not exist (no such flag, and no `list-deleted`
# subcommand) — it errored to stderr, grep got empty stdin, and the `||` branch
# printed "name is free to reuse" no matter what. Module 09 now names the
# server `psql-<workload>-<env>` with no random suffix, so unlike before, a
# fresh apply CAN collide with a dropped server's retained name -- Azure holds
# it for up to 7 days. There is still no step here because there is still no
# command to write one with; `az postgres flexible-server revive-dropped` is
# the recovery counterpart, and docs/TEARDOWN.md carries the procedure.
#
# Module 11 is NOT scoped to TF_VAR_apps here, unlike destroy-container-apps,
# and carries no ASSERT_APPS_COVER_STATE guard the way `apply` does. That
# asymmetry is deliberate: this target tears the whole estate down, so
# destroying every container app is the intent, not an accident. The apply
# loop is guarded because there "destroy an app" is a silent side effect of
# asking to create a different one.
.PHONY: destroy
destroy: check-backend
	@KV_NAME=$$( cd $(ROOTS_DIR)/05-key-vault 2>/dev/null \
	   && terraform init -reconfigure -backend-config=../../envs/$(ENV)/backend.hcl \
	        -backend-config="key=key-vault/terraform.tfstate" >/dev/null 2>&1 \
	   && terraform output -raw kv_name 2>/dev/null || true ); \
	 echo "Pre-destroy capture: KV_NAME='$$KV_NAME'"; \
	 set -e; \
	 if [ -z "$(DIRS_REV)" ]; then \
	   echo "ERROR: DIRS_REV is empty — refusing to run a no-op destroy." >&2; \
	   exit 1; \
	 fi; \
	 for d in $(DIRS_REV); do \
	   if [ "$$d" = "01-resource-groups" ]; then \
	     $(SWEEP_ORPHANS); \
	   fi; \
	   key="$${d#[0-9][0-9]-}"; \
	   echo "=== DESTROY $$d ==="; \
	   ( cd $(ROOTS_DIR)/$$d \
	     && terraform init -reconfigure \
	          -backend-config=../../envs/$(ENV)/backend.hcl \
	          -backend-config="key=$$key/terraform.tfstate" \
	          $(BACKEND_OVERRIDES) \
	     && terraform destroy -auto-approve \
	          $(ENV_VARFILE) ); \
	 done; \
	 if [ -n "$$KV_NAME" ]; then \
	   echo "=== CHECK Key Vault $$KV_NAME ==="; \
	   KV_LOC=$$(az keyvault list-deleted \
	     --query "[?name=='$$KV_NAME'].properties.location | [0]" \
	     -o tsv 2>/dev/null); \
	   if [ -n "$$KV_LOC" ]; then \
	     echo "  soft-deleted vault found in $$KV_LOC — purging"; \
	     az keyvault purge --name "$$KV_NAME" --location "$$KV_LOC"; \
	   else \
	     echo "  already purged by the provider (purge_soft_delete_on_destroy) — nothing to do"; \
	   fi; \
	 fi

# -----------------------------------------------------------------------------
# Whole-estate: reprovision = destroy + apply
# -----------------------------------------------------------------------------
# Recursive $(MAKE) instead of prereqs so `make -jN reprovision` cannot run
# both in parallel. Both steps are idempotent modulo the soft-delete windows
# called out in the module READMEs.
.PHONY: reprovision
reprovision:
	@$(MAKE) destroy
	@$(MAKE) apply

# -----------------------------------------------------------------------------
# Release: version bump, changelog roll, annotated tag
# -----------------------------------------------------------------------------
# Releases are manual and explicit — you pick the bump level, nothing is
# inferred from commit messages. `VERSION` is the source of truth; the tag is
# `v$(VERSION)`; the changelog and the `release` tag on every Azure resource
# both derive from it. `make release-check` prints the policy (what counts as MAJOR
# for infrastructure) and the undo procedure.
#
# The bump targets deliberately stop at the local annotated tag. Pushing is a
# separate, explicit `release-push`, so a mistyped level or a bad changelog
# roll is recoverable with `git tag -d` + `git reset --hard HEAD~1` and never
# escapes the machine.
#
# Portability constraints (same ones as the destroy loop — see the DIRS_REV
# comment): no GNU coreutils on macOS. Bump arithmetic is POSIX `$((...))` over
# an `IFS=. read`, not `seq`/`bc`. The changelog is rewritten through `awk`
# into a temp file and `mv`d, never `sed -i` — BSD `sed -i` demands a backup
# suffix and GNU `sed -i` refuses one, so no single `sed -i` invocation works
# on both this laptop and the ubuntu CI runner.
#
# Every awk program is kept on ONE physical line. A `\`-continuation inside a
# single-quoted awk program would be passed to the shell literally (backslash,
# newline, and the continuation line's leading whitespace all land inside the
# quotes) and awk would choke on it.
#
# Shared bodies live in `define` variables inlined into the recipes, NOT in
# sub-targets invoked via $(MAKE) — same reason as SWEEP_ORPHANS above: a
# $(MAKE) inside a backslash-continued recipe line runs for real under `-n`,
# and `make -n release-patch` must stay an honest dry run.

# Preflight shared by every release target. Read-only: verifies the repo is in
# a fit state to be tagged and exits non-zero otherwise. Deliberately does NOT
# fail on untracked files — `.idea/`-style noise is not a reason to block a
# release, and everything that will be committed is checked above.
#
# The origin sync check compares against FETCH_HEAD rather than
# `refs/remotes/origin/main`, because `git fetch origin main` does not reliably
# update the remote-tracking ref on every git version. A fetch failure is a
# WARNING, not an error, so the release targets still work offline.
define RELEASE_PRECHECK
echo "=== RELEASE PRECHECK ==="; \
if [ ! -f VERSION ]; then \
  echo "ERROR: VERSION file is missing at the repo root." >&2; exit 1; \
fi; \
_v=$$(cat VERSION); \
case "$$_v" in \
  [0-9]*.[0-9]*.[0-9]*) ;; \
  *) echo "ERROR: VERSION '$$_v' is not MAJOR.MINOR.PATCH." >&2; exit 1;; \
esac; \
case "$$_v" in \
  *[!0-9.]*|*.*.*.*|*..*|.*|*.) \
    echo "ERROR: VERSION '$$_v' is not MAJOR.MINOR.PATCH." >&2; exit 1;; \
esac; \
if ! git diff --quiet || ! git diff --cached --quiet; then \
  echo "ERROR: working tree is dirty. Commit or stash before releasing." >&2; \
  git status --short >&2; \
  exit 1; \
fi; \
_br=$$(git rev-parse --abbrev-ref HEAD); \
if [ "$$_br" != "main" ]; then \
  echo "ERROR: releases are cut from main, not '$$_br'." >&2; \
  echo "  This repo is trunk-based: all work lands on main directly, and a" >&2; \
  echo "  release is a bump + tag on main. See make release-check." >&2; \
  exit 1; \
fi; \
if git fetch --quiet origin main 2>/dev/null; then \
  if ! git merge-base --is-ancestor FETCH_HEAD HEAD; then \
    echo "ERROR: HEAD does not contain origin/main." >&2; \
    echo "  Pull main before releasing." >&2; \
    exit 1; \
  fi; \
else \
  echo "  WARN: could not fetch origin, skipping the sync check"; \
fi; \
echo "  ok: VERSION=$$_v, branch=$$_br, tree clean"
endef

# A bump with an empty [Unreleased] section produces a release note that says
# nothing, which is worse than no release at all. Counts `- ` bullets between
# the [Unreleased] heading and the next version heading.
#
# The `#` characters in these awk patterns survive: make passes `#` through a
# define body verbatim, it is only the makefile's own lines that treat it as a
# comment. Anchoring on the full `^## \[` (hash, hash, SPACE, bracket) matters
# — the prose at the top of CHANGELOG.md mentions `[Unreleased]` inline, and a
# looser pattern either misses the real heading or matches the prose.
define RELEASE_REQUIRE_UNRELEASED
_n=$$(awk '/^## \[Unreleased\]/{f=1;next} f && /^## \[[0-9]/{exit} f && /^- /{c++} END{print c+0}' CHANGELOG.md); \
if [ "$$_n" -eq 0 ]; then \
  echo "ERROR: CHANGELOG.md [Unreleased] has no entries - nothing to release." >&2; \
  exit 1; \
fi; \
echo "  ok: $$_n changelog entrie(s) under [Unreleased]"
endef

# Creates the annotated tag for whatever VERSION currently holds. Re-reads the
# file rather than using $(VERSION), because RELEASE_BUMP rewrites VERSION
# after make has already expanded its variables.
define RELEASE_TAG_BODY
_v=$$(cat VERSION); \
_tag="v$$_v"; \
if git rev-parse -q --verify "refs/tags/$$_tag" >/dev/null; then \
  echo "ERROR: tag $$_tag already exists." >&2; exit 1; \
fi; \
git tag -a "$$_tag" -m "Release $$_tag"; \
echo "=== TAGGED $$_tag ==="; \
echo "  nothing has been pushed. Inspect with 'git show --stat HEAD', then:"; \
echo "    make release-push     push main + $$_tag (this publishes the release)"; \
echo "  or undo with:"; \
echo "    git tag -d $$_tag && git reset --hard HEAD~1"; \
echo "  (nothing has left this machine until 'make release-push'.)"
endef

# The bump itself. LEVEL (patch|minor|major) comes from the calling recipe.
# Order matters: every check that can fail runs BEFORE the first write, so a
# rejected release leaves the tree exactly as it found it.
#
# The changelog roll replaces the `## [Unreleased]` heading with a fresh empty
# [Unreleased] block followed by the new version heading. The old Unreleased
# body is left in place and therefore falls under the new version — which is
# precisely the Keep a Changelog promotion.
define RELEASE_BUMP
$(RELEASE_PRECHECK); \
$(RELEASE_REQUIRE_UNRELEASED); \
IFS=. read -r _ma _mi _pa < VERSION; \
case "$$LEVEL" in \
  major) _ma=$$((_ma + 1)); _mi=0; _pa=0;; \
  minor) _mi=$$((_mi + 1)); _pa=0;; \
  patch) _pa=$$((_pa + 1));; \
  *) echo "ERROR: unknown bump level '$$LEVEL'." >&2; exit 1;; \
esac; \
_new="$$_ma.$$_mi.$$_pa"; \
if git rev-parse -q --verify "refs/tags/v$$_new" >/dev/null; then \
  echo "ERROR: tag v$$_new already exists." >&2; exit 1; \
fi; \
echo "=== RELEASE $$LEVEL: $$(cat VERSION) -> $$_new ==="; \
printf '%s\n' "$$_new" > VERSION; \
awk -v ver="$$_new" -v day="$$(date +%F)" 'BEGIN{d=0} /^## \[Unreleased\]/ && !d {print; print ""; print "### Added"; print ""; print "### Changed"; print ""; print "### Fixed"; print ""; print "## [" ver "] - " day; d=1; next} {print}' CHANGELOG.md > CHANGELOG.md.tmp; \
mv CHANGELOG.md.tmp CHANGELOG.md; \
git add VERSION CHANGELOG.md; \
git commit -q -m "release: v$$_new"; \
$(RELEASE_TAG_BODY)
endef

.PHONY: version
version:
	@echo "VERSION file : $(VERSION)"
	@echo "Release tag  : $(RELEASE_TAG)"
	@echo "Latest tag   : $$(git describe --tags --abbrev=0 2>/dev/null || echo '(none yet)')"
	@echo "Estate stamp : every Azure resource carries tags.release = VERSION"

.PHONY: release-check
release-check:
	@$(RELEASE_PRECHECK); \
	 $(RELEASE_REQUIRE_UNRELEASED); \
	 IFS=. read -r _ma _mi _pa < VERSION; \
	 echo ""; \
	 echo "  current        v$$_ma.$$_mi.$$_pa"; \
	 echo "  release-patch  v$$_ma.$$_mi.$$((_pa + 1))   in-place tweaks, docs, no resource churn"; \
	 echo "  release-minor  v$$_ma.$$((_mi + 1)).0   new resources or modules, additive plan"; \
	 echo "  release-major  v$$((_ma + 1)).0.0   destroys/recreates or renames existing resources"

# The three release targets. Each bumps VERSION, rolls the changelog, commits
# and creates the annotated tag -- all LOCALLY. `make release-push` is the
# separate, deliberate step that publishes.
#
# One shot rather than the old prep/tag split: this repo is trunk-based, so the
# release commit is made directly on main and its SHA is the SHA that gets
# pushed. Nothing rewrites it between the tag and the push.
.PHONY: release-patch
release-patch:
	@LEVEL=patch; $(RELEASE_BUMP)

.PHONY: release-minor
release-minor:
	@LEVEL=minor; $(RELEASE_BUMP)

.PHONY: release-major
release-major:
	@LEVEL=major; $(RELEASE_BUMP)

# Tag the CURRENT VERSION without bumping it.
#
# An escape hatch, not part of the normal recipe: it only helps when a bump
# committed cleanly but the tag was lost or deleted before it was pushed.
# Requires the changelog to already carry a section for this version, so it
# cannot mint a tag with no release notes behind it -- which also means it
# cannot be used to cut a NEW release ([Unreleased] carries no version
# heading). Use release-<level> for that.
.PHONY: release-tag
release-tag:
	@$(RELEASE_PRECHECK); \
	 _v=$$(cat VERSION); \
	 if ! grep -q "^## \[$$_v\]" CHANGELOG.md; then \
	   echo "ERROR: CHANGELOG.md has no [$$_v] section. Add one, or use release-<level>." >&2; \
	   exit 1; \
	 fi; \
	 $(RELEASE_TAG_BODY)

# Publishes the commit and the tag. This is the only release target that talks
# to the network, and the only one that is not undoable — a pushed tag is never
# moved.
#
# The tag push fires release.yml, which validates the tag against VERSION and
# CHANGELOG.md and creates the GitHub Release. Pushing the tag IS publishing --
# there is no separate confirmation step after this one.
#
# `git push origin main` comes FIRST and is load-bearing. The release commit
# was made locally on main, so the branch must reach origin before the tag
# does -- push the tag alone and the tag names a commit nobody else can see.
# Both pushes go in one target so the ordering cannot be got wrong by hand.
.PHONY: release-push
release-push:
	@_tag="$(RELEASE_TAG)"; \
	 if ! git rev-parse -q --verify "refs/tags/$$_tag" >/dev/null; then \
	   echo "ERROR: no local tag $$_tag. Run 'make release-<level>' first." >&2; exit 1; \
	 fi; \
	 echo "=== PUSH $$_tag ==="; \
	 git push origin main; \
	 git push origin "$$_tag"; \
	 echo "  pushed. release.yml is now publishing $$_tag:"; \
	 echo "    gh run list --workflow=release.yml"

# -----------------------------------------------------------------------------
# Utility: fmt, check-tfvars, check-backend, validate, list, help
# -----------------------------------------------------------------------------

# `terraform fmt -recursive` walks every .tf under terraform/ (modules AND
# module roots). CI can gate on `terraform fmt -check -recursive terraform/`.
.PHONY: fmt
fmt:
	terraform fmt -recursive terraform/

# Refuse an environment whose selectors disagree with each other.
#
# Three things have to name the same environment on every run, and they arrive
# by three different routes:
#
#   ENV=<x>                 picks $(ENV_DIR)/backend.hcl  -> which state container
#   TF_VAR_env=<x>          names every resource, and picks envs/<x>/tags.json
#   TF_VAR_container_name   OVERRIDES backend.hcl at init (BACKEND_OVERRIDES
#                           is appended after the file, and last one wins)
#
# Any pair can disagree, and none of the mismatches announces itself:
#
#   * ENV=lab with a TF_VAR_container_name left over from a dev session inits
#     lab against DEV's container -- twelve state blobs, silently shared.
#   * ENV=lab with TF_VAR_env=dev writes lab's container but names everything
#     `dev-*` and stamps dev's tags.
#
# Terraform cannot catch either: each value is individually valid, and the
# backend block has no idea what `var.env` says. So compare them here, before
# any init runs. Unset variables are not an error -- backend.hcl stands alone
# then, and `var.container_name` is required, so a missing export already
# fails loudly with the variable's name.
.PHONY: check-backend
check-backend:
	@f="$(ENV_DIR)/backend.hcl"; \
	 if [ ! -f "$$f" ]; then \
	   echo "ERROR: no backend.hcl for ENV=$(ENV) (looked in $(ENV_DIR)/)."; \
	   echo "Environments with a config directory:"; \
	   ls -d terraform/envs/*/ 2>/dev/null | sed 's#.*/envs/#  #; s#/$$##'; \
	   exit 1; \
	 fi; \
	 hcl() { sed -n "s/^[[:space:]]*$$1[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$$/\1/p" "$$f" | head -1; }; \
	 bad=""; \
	 if [ -n "$$TF_VAR_env" ] && [ "$$TF_VAR_env" != "$(ENV)" ]; then \
	   bad="$$bad\n  TF_VAR_env='$$TF_VAR_env' but ENV=$(ENV) selects $(ENV_DIR)/"; \
	 fi; \
	 for pair in "container_name:$$TF_VAR_container_name" \
	             "storage_account_name:$$TF_VAR_storage_account_id" \
	             "resource_group_name:$$TF_VAR_backend_resource_group_name"; do \
	   key="$${pair%%:*}"; want="$${pair#*:}"; \
	   [ -n "$$want" ] || continue; \
	   have=$$(hcl "$$key"); \
	   [ -n "$$have" ] || continue; \
	   if [ "$$have" != "$$want" ]; then \
	     bad="$$bad\n  $$key: backend.hcl has '$$have', environment has '$$want' (environment wins at init)"; \
	   fi; \
	 done; \
	 if [ -n "$$bad" ]; then \
	   echo "ERROR: ENV=$(ENV) disagrees with the environment:"; \
	   printf '%b\n' "$$bad"; \
	   echo ""; \
	   echo "Fix the export, or run a different ENV. Left alone this reads or"; \
	   echo "writes another environment's state without saying so."; \
	   exit 1; \
	 fi; \
	 echo "clean: ENV=$(ENV) agrees with backend.hcl and the environment"

# Refuse an auto-loaded var file inside a shared module root.
#
# Terraform auto-loads `terraform.tfvars`, `terraform.tfvars.json` and any
# `*.auto.tfvars` from the directory it runs in -- no flag, and no mention of
# it in the plan header. That was harmless while a root belonged to one
# environment. The roots under $(ROOTS_DIR) are now shared by all of them, so
# such a file applies to dev, lab and everything after alike, and it outranks
# TF_VAR_* -- it wins over the very mechanism that was supposed to carry the
# per-environment difference. Nothing in the output says so.
#
# .gitignore (*.tfvars) already keeps these out of commits. This catches the
# local copy, which is the one that changes what a shared root does; the CI
# run catches a `git add -f`.
#
# Per-environment values belong in $(ENV_DIR)/env.tfvars or a TF_VAR_ export.
.PHONY: check-tfvars
check-tfvars:
	@found=$$(find $(ROOTS_DIR) \
	    \( -name 'terraform.tfvars'      -o -name 'terraform.tfvars.json' \
	       -o -name '*.auto.tfvars'      -o -name '*.auto.tfvars.json' \) \
	    -not -path '*/.terraform/*' 2>/dev/null); \
	 if [ -n "$$found" ]; then \
	   echo "ERROR: auto-loaded var file inside a shared module root:"; \
	   echo "$$found" | sed 's/^/  /'; \
	   echo ""; \
	   echo "Roots under $(ROOTS_DIR) are shared by every environment, and these"; \
	   echo "files are auto-loaded and outrank TF_VAR_*. Move the values to"; \
	   echo "$(ENV_DIR)/env.tfvars, or export them as TF_VAR_<name>."; \
	   exit 1; \
	 fi; \
	 echo "clean: no auto-loaded var file under $(ROOTS_DIR)"

# `terraform validate` per module root. `-backend=false` skips the remote-
# state login — validate is syntactic + schema-level only, no cloud calls.
#
# Depends on check-tfvars because `make fmt && make validate` is the documented
# pre-commit gate: a guard nothing runs locally is half a guard.
.PHONY: validate
validate: check-tfvars
	@set -e; for d in $(DIRS); do \
	  echo "=== VALIDATE $$d ==="; \
	  ( cd $(ROOTS_DIR)/$$d \
	    && terraform init -reconfigure -backend=false >/dev/null \
	    && terraform validate ); \
	done

# -----------------------------------------------------------------------------
# State backup
# -----------------------------------------------------------------------------
# Download every module root's state from the backend into STATE_DIR as JSON,
# one file per module.
#
# There is no local state to back up -- the azurerm backend holds the only
# copy, and .terraform/terraform.tfstate is a backend POINTER, not state. This
# target exists for the cases the backend cannot serve: reading state without a
# working Terraform (grep for a resource ID, diff two points in time), and
# keeping a copy somewhere other than the subscription that the state describes.
#
# It is NOT the primary recovery path. bootstrap-backend enables blob
# versioning and soft delete on the account, so recovering a clobbered state is
# a blob version restore, which keeps the serial and lineage intact. A file
# from here restored with `terraform state push` needs its serial reasoned
# about by hand.
#
# Read-only against Azure: `state pull` takes no lock and changes nothing. Safe
# to run at any time, including mid-incident.
#
# Output is gitignored (.gitignore: misc/state-backup/). State files contain
# every attribute of every resource, INCLUDING values marked sensitive in
# outputs -- connection strings, generated passwords, keys. Treat the directory
# as a secret. Never commit it, never paste it into an issue.
STATE_DIR ?= misc/state-backup

.PHONY: pull-state
pull-state: check-backend
	@mkdir -p $(STATE_DIR)
	@set -e; for d in $(DIRS); do \
	  key="$${d#[0-9][0-9]-}"; \
	  echo "=== PULL $$d ==="; \
	  ( cd $(ROOTS_DIR)/$$d \
	    && terraform init -reconfigure \
	         -backend-config=../../envs/$(ENV)/backend.hcl \
	         -backend-config="key=$$key/terraform.tfstate" \
	         $(BACKEND_OVERRIDES) >/dev/null \
	    && terraform state pull ) > $(STATE_DIR)/$$key.json; \
	  if [ ! -s $(STATE_DIR)/$$key.json ]; then \
	    echo "  (no state yet -- removing empty file)"; \
	    rm -f $(STATE_DIR)/$$key.json; \
	  fi; \
	done
	@echo "State written to $(STATE_DIR)/ -- contains secrets, do not commit."

# Run the same SonarCloud scan CI runs. LOCAL FALLBACK ONLY -- this is NOT part
# of the release recipe.
#
# It used to be: release.yml fires on a tag that is ALREADY pushed, and
# A published tag is never moved, so a red gate discovered in CI
# cost a whole patch release and there was no earlier gate. That reason is gone.
# main-verify.yml runs the same scan on main when asked, so the gate can report
# on the release commit before you tag, and release.yml can scan again on a
# dispatch with run_sonar=true. Reach for this only to reproduce a CI Sonar
# failure locally.
#
# Configuration comes entirely from sonar-project.properties, exactly as in CI,
# so this and the workflow cannot drift. No scanner arguments are passed.
#
# Uses the official scanner image because sonar-scanner is not installed by
# default on macOS and Docker is; the image bundles its own JRE.
#
# The GIT_CONFIG_* trio is load-bearing, and its absence does not look like a
# config problem -- it looks like a hang. The container runs as uid 1000 while
# the bind-mounted tree is owned by the host user, so git refuses the repo with
# "detected dubious ownership in repository at /usr/src". The scanner's SCM
# publisher then cannot use the native git blame path and falls back to walking
# the history itself, which on an emulated x86 image over a macOS bind mount
# crawls -- the run appears to stop dead at "SCM Publisher N source files to be
# analyzed". Setting safe.directory through the environment fixes THAT failure
# -- git can read the repo again -- but do not expect it to make the step fast;
# see the Apple Silicon note below.
#
# Blame data is not optional here: SonarCloud attributes findings to NEW code
# from it, and the quality gate conditions are all new_* metrics. Do not "fix" a
# slow SCM step with sonar.scm.disabled=true -- that would silently change which
# findings the gate counts, and this target's whole value is matching CI.
#
# ON APPLE SILICON THIS IS SLOW ENOUGH TO LOOK BROKEN. The image is amd64-only
# and runs under emulation, and the scanner's SCM publisher blames through JGit
# rather than the git CLI: measured at MINUTES for ~144 files, where a native
# `git blame` over the same files takes about one second. "SCM blame is in
# progress.." means it is working, not hung -- but budget for the wait, or just
# let CI do it, which is the whole point of main-verify.yml. A merge commit in
# the history makes it worse, because JGit walks both parents.
#
# WARNING: this PUBLISHES results to SonarCloud and they become the project's
# current state for the branch. Run it on a clean tree at the commit you intend
# to tag, not over work in progress -- otherwise the project ends up reporting
# on code that was never committed.
#
# MAIN ONLY, and the guard below enforces it. sonar.branch.name=main is pinned
# in sonar-project.properties (this repo is trunk-based -- main is the only
# branch there is to analyse), so no scanner argument is passed here. Running
# it from a scratch branch would publish that branch's code AS main's analysis
# and hand main a quality gate result for code that was never on it.
.PHONY: sonar
sonar:
	@_br=$$(git rev-parse --abbrev-ref HEAD); \
	 if [ "$$_br" != "main" ]; then \
	   echo "ERROR: 'make sonar' analyses main, but you are on '$$_br'." >&2; \
	   echo "  Running it here would publish this branch's code as main's" >&2; \
	   echo "  analysis. Switch to main first." >&2; \
	   exit 1; \
	 fi
	@if [ -z "$$SONAR_TOKEN" ]; then \
	  echo "ERROR: SONAR_TOKEN is not set. Export it before running 'make sonar'." >&2; \
	  echo "It is an organization Actions secret on rubensgomes-org; generate a" >&2; \
	  echo "local token at https://sonarcloud.io -> My Account -> Security." >&2; \
	  exit 1; \
	fi
	docker run --rm -e SONAR_TOKEN \
	  -e GIT_CONFIG_COUNT=1 \
	  -e GIT_CONFIG_KEY_0=safe.directory \
	  -e GIT_CONFIG_VALUE_0=/usr/src \
	  -v "$(CURDIR):/usr/src" \
	  sonarsource/sonar-scanner-cli:latest

.PHONY: list
list:
	@echo "Modules (dependency order):"
	@for d in $(DIRS); do echo "  $$d"; done

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Per-module (short-name suffix, e.g. 'key-vault' not '05-key-vault'):"
	@echo "  init-<name>       terraform init  (with correct backend key)"
	@echo "  plan-<name>       terraform plan  -out=tfplan"
	@echo "  plan-destroy-<name>  terraform plan -destroy -out=tfplan (preview only)"
	@echo "  apply-<name>      terraform apply -auto-approve"
	@echo "  destroy-<name>    terraform destroy -auto-approve"
	@echo ""
	@echo "  container-apps is the exception: its plan/apply/destroy targets"
	@echo "  act ONLY on the apps named in TF_VAR_apps, one -target each."
	@echo ""
	@echo "Whole-estate:"
	@echo "  apply             Apply all modules 01 -> 12"
	@echo "  destroy           Destroy all modules 12 -> 01, sweeping Azure-generated"
	@echo "                    orphans before 01 and verifying the KV is purged"
	@echo "  purge-orphans     Delete Azure-generated leftovers (Smart Detection"
	@echo "                    action group) that block the RG delete in module 01"
	@echo "  reprovision       destroy, then apply"
	@echo ""
	@echo "Release:"
	@echo "  version           Show VERSION, the derived tag, and the latest git tag"
	@echo "  release-check     Preflight only. Reports what each bump would produce"
	@echo "  release-patch     Bump PATCH, roll changelog, commit, tag. Local only"
	@echo "  release-minor     Bump MINOR, roll changelog, commit, tag. Local only"
	@echo "  release-major     Bump MAJOR, roll changelog, commit, tag. Local only"
	@echo "  release-tag       Tag the current VERSION without bumping (escape hatch)"
	@echo "  release-push      Push main + the tag. Not undoable. The tag push"
	@echo "                    fires release.yml, which publishes the Release"
	@echo ""
	@echo "Utility:"
	@echo "  fmt               terraform fmt -recursive terraform/"
	@echo "  check-tfvars      Refuse an auto-loaded tfvars inside a shared root"
	@echo "  check-backend     Refuse ENV / TF_VAR_env / backend.hcl disagreeing"
	@echo "  validate          terraform validate every module root (no cloud calls)"
	@echo "  pull-state        Download every module's state from the backend into"
	@echo "                    $(STATE_DIR)/ as JSON. Read-only. Output holds"
	@echo "                    secrets -- gitignored, never commit it"
	@echo "  sonar             SonarCloud scan of main. LOCAL FALLBACK only -- CI"
	@echo "                    scans every push to main. Needs SONAR_TOKEN + docker,"
	@echo "                    refuses to run off main, very slow on Apple Silicon"
	@echo "  list              Show all modules in dependency order"
	@echo "  help              This message"
	@echo ""
	@echo "Overrides:"
	@echo "  ENV=<env>         Config directory under terraform/envs/ (default: lab)."
	@echo "                    Selects backend.hcl, tags.json and env.tfvars; the"
	@echo "                    module roots in terraform/roots/ are shared"
	@echo ""
	@echo "Prereqs: ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID /"
	@echo "ARM_SUBSCRIPTION_ID exported in the shell. See docs/INITIAL_SETUP.md."
