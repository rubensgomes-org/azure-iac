# Root Makefile — dev-estate automation (§10 of docs/PROVISIONING_PLAN.md).
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
#     for apply, 12→01 for destroy). Both are §14's shell blocks lifted in
#     verbatim, so the Makefile stays honest to the plan.
#
#   * `destroy` also runs the post-destroy Key Vault purge (dev toggle,
#     purge_protection = false) and reports any soft-deleted PG server
#     still holding the name. Same block as §14.
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
#     Match the §14 script. For safe review, run `plan-<name>` first.
#
#   * `terraform init -reconfigure` on every invocation. Cheap (cached
#     provider plugins), and immune to the "backend key drifted" class of
#     bug that ate an afternoon during the 05/07 state-corruption incident.
#
# Assumes ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID /
# ARM_SUBSCRIPTION_ID are exported in the shell. See terraform/INITIAL_SETUP.md.
# -----------------------------------------------------------------------------

ENV     ?= dev
ENV_DIR := terraform/envs/$(ENV)

# Release version. The repo-root VERSION file is the single source of truth:
# the git tag is `v$(VERSION)`, the CHANGELOG heading is `[$(VERSION)]`, and
# every module root reads the same file to stamp a `release` tag onto every
# Azure resource. See RELEASING.md.
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

# Destroy order is the strict reverse of DIRS (§7 of the plan). Reversing is
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

init-$(2):
	@echo "=== INIT $(1) ==="
	@cd $(ENV_DIR)/$(1) && terraform init -reconfigure \
	  -backend-config=../backend.hcl \
	  -backend-config="key=$(2)/terraform.tfstate"

plan-$(2): init-$(2)
	@echo "=== PLAN $(1) ==="
	@cd $(ENV_DIR)/$(1) && terraform plan \
	  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan

# Speculative TEARDOWN plan. Writes the same `tfplan` filename as plan-$(2),
# so the two overwrite each other — that is deliberate: a stale plan file of
# the wrong polarity is far more dangerous than no plan file at all. Nothing
# consumes the artifact (destroy-$(2) re-plans internally under
# -auto-approve); it exists to be READ, by eye or by `terraform show -json`.
plan-destroy-$(2): init-$(2)
	@echo "=== PLAN -destroy $(1) ==="
	@cd $(ENV_DIR)/$(1) && terraform plan -destroy \
	  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan

apply-$(2): init-$(2)
	@echo "=== APPLY $(1) ==="
	@cd $(ENV_DIR)/$(1) && terraform apply -auto-approve \
	  -var-file=../env.tfvars -var-file=terraform.tfvars

destroy-$(2): init-$(2)
	@echo "=== DESTROY $(1) ==="
	@cd $(ENV_DIR)/$(1) && terraform destroy -auto-approve \
	  -var-file=../env.tfvars -var-file=terraform.tfvars
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
$(eval $(call MODULE_TARGETS,11-container-apps,container-apps))
$(eval $(call MODULE_TARGETS,12-monitoring,monitoring))

# -----------------------------------------------------------------------------
# Whole-estate: apply (01 → 12)
# -----------------------------------------------------------------------------
# Verbatim from §14 of docs/PROVISIONING_PLAN.md — kept in a shell for-loop so
# ordering is strictly serial regardless of `make -jN`.
.PHONY: apply
apply:
	@set -e; for d in $(DIRS); do \
	  key="$${d#[0-9][0-9]-}"; \
	  echo "=== APPLY $$d ==="; \
	  ( cd $(ENV_DIR)/$$d \
	    && terraform init -reconfigure \
	         -backend-config=../backend.hcl \
	         -backend-config="key=$$key/terraform.tfstate" \
	    && terraform apply -auto-approve \
	         -var-file=../env.tfvars -var-file=terraform.tfvars ); \
	done

# -----------------------------------------------------------------------------
# Orphan sweep — Azure-generated resources Terraform never owned
# -----------------------------------------------------------------------------
# Creating an Application Insights component makes Azure ALSO create an action
# group named "Application Insights Smart Detection" in the same RG. Terraform
# never manages it, so destroying module 12 leaves it behind — and then module
# 01 cannot delete rg-dev-observability, because azurerm's
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
echo "=== SWEEP Azure-generated orphans (rg-dev-observability) ==="; \
ids=$$(az monitor action-group list -g rg-dev-observability \
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
# There is deliberately NO PostgreSQL step. `az postgres flexible-server list
# --show-deleted` does not exist (no such flag, and no `list-deleted`
# subcommand) — it errored to stderr, grep got empty stdin, and the `||` branch
# printed "name is free to reuse" no matter what. It is also moot: module 09
# names the server `psql-<env>-<random_id>`, so a fresh apply never collides
# with a dropped server's retained name. `az postgres flexible-server
# revive-dropped` is the recovery counterpart if you ever need one back.
.PHONY: destroy
destroy:
	@KV_NAME=$$( cd $(ENV_DIR)/05-key-vault 2>/dev/null \
	   && terraform init -reconfigure -backend-config=../backend.hcl \
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
	   ( cd $(ENV_DIR)/$$d \
	     && terraform init -reconfigure \
	          -backend-config=../backend.hcl \
	          -backend-config="key=$$key/terraform.tfstate" \
	     && terraform destroy -auto-approve \
	          -var-file=../env.tfvars -var-file=terraform.tfvars ); \
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
# called out in §9.
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
# both derive from it. RELEASING.md documents the policy (what counts as MAJOR
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
  echo "  release is a bump + tag on main. See RELEASING.md." >&2; \
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
echo "    make release-push     publish $$_tag (fires release.yml)"; \
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

# Publishes. This is the only release target that talks to the network, and
# the only one that is not undoable — release.yml fires on the tag.
#
# `git push origin main` comes FIRST and is load-bearing. The release commit
# was made locally on main, so the branch must reach origin before the tag
# does -- push the tag alone and release.yml fires against a commit nobody
# else can see. Both pushes go in one target so the ordering cannot be got
# wrong by hand.
.PHONY: release-push
release-push:
	@_tag="$(RELEASE_TAG)"; \
	 if ! git rev-parse -q --verify "refs/tags/$$_tag" >/dev/null; then \
	   echo "ERROR: no local tag $$_tag. Run 'make release-<level>' first." >&2; exit 1; \
	 fi; \
	 echo "=== PUSH $$_tag ==="; \
	 git push origin main; \
	 git push origin "$$_tag"; \
	 echo "  pushed. Watch: gh run list --workflow=release.yml"

# -----------------------------------------------------------------------------
# Utility: fmt, validate, list, help
# -----------------------------------------------------------------------------

# `terraform fmt -recursive` walks every .tf under terraform/ (modules AND
# module roots). CI can gate on `terraform fmt -check -recursive terraform/`.
.PHONY: fmt
fmt:
	terraform fmt -recursive terraform/

# `terraform validate` per module root. `-backend=false` skips the remote-
# state login — validate is syntactic + schema-level only, no cloud calls.
.PHONY: validate
validate:
	@set -e; for d in $(DIRS); do \
	  echo "=== VALIDATE $$d ==="; \
	  ( cd $(ENV_DIR)/$$d \
	    && terraform init -reconfigure -backend=false >/dev/null \
	    && terraform validate ); \
	done

# Run the same SonarCloud scan CI runs. LOCAL FALLBACK ONLY -- this is NOT part
# of the release recipe. See RELEASING.md.
#
# It used to be: release.yml fires on a tag that is ALREADY pushed, and
# RELEASING.md forbids moving a published tag, so a red gate discovered in CI
# cost a whole patch release and there was no earlier gate. That reason is gone.
# main-verify.yml runs the same scan on every push to main, so the gate has
# already reported on the release commit by the time you tag, and release.yml
# scans again at tag time. Reach for this only to reproduce a CI Sonar failure
# locally.
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
	@echo "Whole-estate:"
	@echo "  apply             Apply all modules 01 -> 12"
	@echo "  destroy           Destroy all modules 12 -> 01, sweeping Azure-generated"
	@echo "                    orphans before 01 and verifying the KV is purged"
	@echo "  purge-orphans     Delete Azure-generated leftovers (Smart Detection"
	@echo "                    action group) that block the RG delete in module 01"
	@echo "  reprovision       destroy, then apply"
	@echo ""
	@echo "Release (see RELEASING.md):"
	@echo "  version           Show VERSION, the derived tag, and the latest git tag"
	@echo "  release-check     Preflight only. Reports what each bump would produce"
	@echo "  release-patch     Bump PATCH, roll changelog, commit, tag. Local only"
	@echo "  release-minor     Bump MINOR, roll changelog, commit, tag. Local only"
	@echo "  release-major     Bump MAJOR, roll changelog, commit, tag. Local only"
	@echo "  release-tag       Tag the current VERSION without bumping (escape hatch)"
	@echo "  release-push      Push main + the tag. Fires release.yml. Not undoable"
	@echo ""
	@echo "Utility:"
	@echo "  fmt               terraform fmt -recursive terraform/"
	@echo "  validate          terraform validate every module root (no cloud calls)"
	@echo "  sonar             SonarCloud scan of main. LOCAL FALLBACK only -- CI"
	@echo "                    scans every push to main. Needs SONAR_TOKEN + docker,"
	@echo "                    refuses to run off main, very slow on Apple Silicon"
	@echo "  list              Show all modules in dependency order"
	@echo "  help              This message"
	@echo ""
	@echo "Overrides:"
	@echo "  ENV=<env>         Environment directory under terraform/envs/ (default: dev)"
	@echo ""
	@echo "Prereqs: ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID /"
	@echo "ARM_SUBSCRIPTION_ID exported in the shell. See terraform/INITIAL_SETUP.md."
