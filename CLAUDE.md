# CLAUDE.md

Pointer file for future Claude Code sessions working on this repo.

## What this project is

A learning-playground Azure IaC project. Terraform provisions a fixed set of
Azure resources (Resource Groups, VNet, Log Analytics, Managed Identity, Key
Vault, ACR, Storage, Service Bus, PostgreSQL Flexible, Container App
Environment, Container Apps, Monitoring; APIM deferred to a second
iteration). Microservice apps (Java 25 / Spring Boot 4.1.x) will be deployed
into the Container App environment and authenticate to every Azure service
passwordlessly via a single shared User-Assigned Managed Identity.

## Where the master plan lives

**`docs/PROVISIONING_PLAN.md`** — dependency order, RG partitioning, naming
conventions, per-module scaffolding, workflow commands, passwordless auth
model, verification checklists. **§15 is the authoritative complete-teardown
procedure** (prereqs, verification, what legitimately survives, removing the
state backend, and the two ways a destroy can silently do nothing).

Always read that file before making infra decisions.

## Project status (as of 2026-08-24)

**Paused — estate is feature-complete in code.** All 12 modules
(01-resource-groups through 12-monitoring) are implemented and have been
applied and verified against Azure at least once. The root `Makefile` is in
place; `make validate` was last run clean across every module root.

**Currently applied: module 01-resource-groups ONLY. Everything else is
torn down.** Verified against Azure on 2026-08-24: the five RGs
(`rg-dev-platform`, `-network`, `-data`, `-app`, `-observability`) exist and
are all **empty** — `az resource list -g <rg>` returns nothing for every one
of them. In the tfstate container only `resource-groups/terraform.tfstate`
is populated (~10 KB); every other module's state key is an empty
few-hundred-byte shell.

Nothing is running, so the estate currently costs $0/month — RGs and the
state Storage Account are free at this scale.

Quick way to re-check this claim rather than trusting the note:

```bash
az group list --query "[].name" -o tsv
az resource list -g rg-dev-platform -o tsv          # empty => nothing applied
az storage blob list --account-name sttfstaterubens01 \
  --container-name tfstate --auth-mode key \
  --query "[].{name:name,size:properties.contentLength}" -o table
```

A state blob under ~500 bytes is an empty shell (serial + lineage, no
resources). Note `--auth-mode key`: the interactive user account holds no
`Storage Blob Data *` role, so `--auth-mode login` fails on that container.

**Rebuilding from here** is `make apply` from repo root (01 is already up and
will no-op), or module-by-module in numeric order. Each module's upstreams
must be applied first — a root whose `data.terraform_remote_state` points at
an empty state key fails at plan with *Unsupported attribute*, not with a
useful message. Minimum chains worth knowing:

- ACR only: `make apply-managed-identities && make apply-acr` (06 needs 04's
  UAMI for the `AcrPull` grant, and 01's platform RG). ~$5.07/month, all of
  it the Basic registry unit.
- Container Apps: 01, 04, 06, 07, 08, 09, 10, then 11.

When resuming, read `docs/PROVISIONING_PLAN.md` → **Deferred work** (right
after the Progress section) for the outstanding items:

- **D1**: swap the placeholder container image in module 11 once real
  Spring Boot images are pushed to ACR (app-work blocked). With 11
  destroyed this is an apply with `apps_image_map` set — but note the
  registry no longer exists either, so ACR has to be reprovisioned and the
  images repushed first. The registry name is now FIXED at `rubensdevacr`
  (set in `terraform/envs/dev/06-acr/terraform.tfvars`), so it survives a
  destroy+recreate and is safe to hardcode in image tags — that was the
  point of dropping the old `acr<env><random>` scheme.
- **D2**: wire `APPLICATIONINSIGHTS_CONNECTION_STRING` into container
  apps (depends on D1).
- **D3**: §12a — PG data-plane bootstrap Container Apps Job (replaces
  the manual Cloud Shell workflow; nice-to-have).
- **D4**: APIM — always-deferred iteration-2 work.

Nothing else is outstanding. `make apply` / `make destroy` from repo
root drives the whole estate; per-module `make apply-<short-name>`
handles one at a time.

## Release process

Every release is a `MAJOR.MINOR.PATCH` git tag on `main`. Read
**`RELEASING.md`** before touching anything release-related;
`docs/PROVISIONING_PLAN.md` §16 has the design rationale.

- Repo-root **`VERSION`** (bare `0.0.1`, no `v`) is the single source of
  truth. The tag is `v$(cat VERSION)`; the `CHANGELOG.md` heading and the
  `release` tag on every Azure resource both derive from it.
- Semver is **infra-impact based**: MAJOR = `plan` destroys/recreates or
  renames an existing resource; MINOR = additive; PATCH = in-place only.
  Project stays at `0.x` until D1/D2 close and a full `make apply` from zero
  verifies clean.
- Bumps are **manual and explicit**: `make release-patch|minor|major` writes
  `VERSION`, rolls `[Unreleased]` into a dated section, commits, and creates
  the annotated tag — **locally**. `make release-push` is the separate,
  network-touching, non-undoable step. `make release-tag` tags the current
  `VERSION` without bumping. **No release has been cut yet** — the repo was
  recreated fresh, so `git tag -l` is empty and `CHANGELOG.md` holds only
  `[Unreleased]`. `v0.0.1` will be the first tag.
- Every module root has a `locals.tf` reading `VERSION` off disk
  (`trimspace(file("${path.root}/../../../../VERSION"))`) and merges
  `release = local.release` into `var.tags`. Read from disk, not passed as
  `-var`, so a bare `terraform apply` typed by hand stamps the same value.
- `.github/workflows/release.yml` fires on `v*.*.*`: checks tag ==
  `VERSION` == a `CHANGELOG.md` section, runs `fmt -check` + `make validate`,
  publishes a GitHub Release. **`release.yml` specifically holds no Azure
  credentials — keep it that way.** Other workflows in this repo do hold
  them; see the CI section below.

## CI — GitHub Actions

Four workflows, two credential models. All Azure-touching workflows get
`ARM_*` from GitHub secrets holding the same `terraform-sp` Service Principal
documented under Auth model.

| Workflow | Actions-tab name | Trigger | Touches Azure | Secret source |
| --- | --- | --- | --- | --- |
| `release.yml` | Release (tag push) | tag `v*.*.*` | **no** | — |
| `provision-acr.yml` | Provision ACR (reusable) | `workflow_call` + `workflow_dispatch` | yes | **org**-level Actions secrets |
| `terraform-bootstrap-apply.yml` | TF Bootstrap Create | `workflow_dispatch` | yes | **Environment** `AZURE` |
| `terraform-bootstrap-destroy.yml` | TF Bootstrap Destroy | `workflow_dispatch` | yes | **Environment** `AZURE` |

The filename and the `name:` differ deliberately — the filename encodes what
the workflow *is*, the `name:` is what reads well in the Actions sidebar. When
renaming either, update both this table and README.md; nothing else in the repo
keys off a workflow's display name.

**`provision-acr.yml` is a reusable workflow** — the CI equivalent of
`PROVISION_ACR.md`. It runs `make init/plan/apply` for modules 01, 04, and 06
in order and publishes `acr_name` / `acr_login_server` as workflow outputs, so
an application repo can gate its image push on it with `needs:`. First
consumer: `rubensgomes-org/spring-blueprint`.

Things to know before editing it:

- It reimplements nothing — it exports `ARM_*` and calls repo-root `make`
  targets, passing `ENV=` through from the `environment_name` input. Keep it
  that way: fix the Makefile, not the workflow.
- It is deliberately **not** bound to a GitHub Environment. For a reusable
  workflow, `environment:` resolves in the *caller's* repo, so binding
  `AZURE` here would silently force every caller to define one. The bootstrap
  workflows are not reusable, so they can and do bind it.
- Its `plan-*` steps **gate nothing** — `apply-<name>` re-plans internally
  under `-auto-approve` and never reads the `tfplan` that `plan-<name>` wrote.
  They exist for log visibility only.
- `concurrency` is evaluated in the repo that owns the run, so a caller's run
  does not serialise against this repo's own. The azurerm blob lease is the
  real guard — a collision fails with a lock error. Never add `-lock=false`.

`.github/actions/import-state/` is a composite action used only by the
bootstrap workflows. Its premise ("Terraform is using the local backend") is
false — `terraform/bootstrap-backend/backend.tf` hardcodes an azurerm backend
— so its three imports always no-op via their `terraform state show` guards.
Each import swallows failure with `|| WARN … continuing anyway`, so if a guard
ever stopped holding, a failed import would fall through to planning a
*create* of a resource that already exists.

All four workflows pin `terraform_version: "1.15.8"` and
`terraform_wrapper: false` (the wrapper intercepts stdout and would break
`terraform output -raw`). Bump the pin in all four together.

## Repo layout (high level)

- `.github/workflows/` — four workflows; see the CI section above.
- `.github/actions/import-state/` — composite action, bootstrap workflows only.
- `PROVISION_ACR.md` — standalone runbook for provisioning/destroying just the
  ACR (modules 01 → 04 → 06), by hand or via `provision-acr.yml`.
- `terraform/bootstrap-backend/` — the state backend module. Already
  provisioned (`rg-tfstate`, `sttfstaterubens01`, `tfstate` container).
  Do not touch unless re-bootstrapping.
- `terraform/modules/<name>/` — reusable child modules. No state, no backend.
- `terraform/envs/dev/env.tfvars` — shared env vars (env, location, prefix,
  apps list, tags, PG Entra admin group ID).
- `terraform/envs/dev/backend.hcl` — shared azurerm backend config.
- `terraform/envs/dev/<NN-module>/` — per-module Terraform root. Own state
  key `<module>/terraform.tfstate` inside the tfstate container. Numeric
  prefix encodes dependency order.
- `docs/PROVISIONING_PLAN.md` — the master plan.
- `terraform/INITIAL_SETUP.md` — one-time SP creation, provider registration,
  ARM_* env vars.

## Auth model

Terraform authenticates to Azure via **Service Principal + client secret**
supplied through environment variables:

- `ARM_CLIENT_ID`
- `ARM_CLIENT_SECRET`
- `ARM_TENANT_ID`
- `ARM_SUBSCRIPTION_ID`

**Never** put credentials in `.tf` or `.tfvars` files. The `providers.tf` in
every module just declares `provider "azurerm" { features {} }` — the
provider picks up ARM_* from the environment.

Application runtime auth is **passwordless via UAMI**. See
`docs/PROVISIONING_PLAN.md` §12 for the wiring across PG, Blob, Service Bus,
Key Vault, and ACR.

## Per-module workflow

From `terraform/envs/dev/<NN-module>/`:

```bash
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=<module>/terraform.tfstate"

terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan

# Verify via `az` CLI (module-specific — see the module's README).

terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
# Then run module-specific purge commands (Key Vault, later APIM).
```

Modules are applied in numeric order (01 → 12) and destroyed in reverse
(12 → 01). The root `Makefile` automates both — `make apply` / `make destroy`
for the whole estate, `make <verb>-<short-name>` for one module. For a full
teardown to zero, follow `docs/PROVISIONING_PLAN.md` §15 rather than running
the per-module commands by hand.

## Common gotchas

- **Backend blocks are empty**. `-backend-config=../backend.hcl` supplies
  literals at init time; `-backend-config="key=..."` supplies the per-module
  state path. If you edit `backend.hcl`, re-run `terraform init -reconfigure`
  in each module.
- **Key Vault soft-delete needs no manual purge**. Dev settings use
  `purge_protection_enabled = false` and `soft_delete_retention_days = 7`, but
  module 05's `features {}` leaves `key_vault.purge_soft_delete_on_destroy` at
  its default `true` — the provider purges during destroy. Running
  `az keyvault purge` afterwards fails with `DeletedVaultNotFound`, which reads
  as breakage but means it already worked.
- **Azure litters an action group into `rg-dev-observability`**. Creating an
  Application Insights component makes Azure also create
  `Application Insights Smart Detection`, which Terraform never owns. It
  survives module 12's destroy and then blocks module 01's RG delete via
  `prevent_deletion_if_contains_resources`. Recurs every teardown;
  `make destroy` sweeps it automatically, `make purge-orphans` does it alone.
  Delete by `--ids`, never `-n` — the name has spaces and az mis-parses it.
- **Several documented `az` flags don't exist**. `az postgres flexible-server
  list --show-deleted` is not a real command (no `list-deleted` either) and
  used to fail silently into a `|| true` that reported success. Verify az
  invocations actually work before trusting them in a recipe.
- **PostgreSQL Entra-only auth**. The Terraform SP must be a member of the
  Entra group referenced by `pg_entra_admin_group_object_id` in `env.tfvars`.
  Without membership, module 09's data-plane step (registering the shared
  UAMI as a PG role) fails.
- **Destroy order matters**. Delegated subnets (`snet-app`, `snet-pg`) will
  refuse to destroy while their delegated resources exist. Always tear down
  container-apps → CAE → PG before networking.
- **Never put `$(MAKE)` inside a multi-command recipe line**. GNU Make executes
  any recipe line containing `$(MAKE)` even under `-n`. Because `destroy` is
  one backslash-continued logical line, a `$(MAKE)` in it made `make -n destroy`
  run the whole teardown for real. Shared shell logic goes in a `define`
  variable inlined into the recipe (see `SWEEP_ORPHANS`). A `$(MAKE)` on its
  own recipe line — as in `reprovision` — is fine: the sub-make inherits `-n`.
- **No GNU coreutils on macOS**. Neither `tac` nor `timeout` exists here. The Makefile's
  destroy loop used to build its module list with `... | tac`, which returned
  empty on darwin, iterated zero times, and reported success having destroyed
  nothing — surfacing only as a baffling `DeletedVaultNotFound` from the purge
  step that follows. Reversal is now done in pure Make. Don't reintroduce
  shell-level GNU-only tools (`tac`, `seq`, `readlink -f`, `xargs -r`,
  `sed -i` without a suffix) in Makefile recipes.
- **PG child-resource deletes time out at 30 minutes**. Destroying module 09
  routinely stalls, then fails on all five children at once (2 firewall rules,
  2 databases, the Entra admin) with `HTTP response was nil` or
  `context deadline exceeded`. Azure serializes control-plane ops on the
  server, so the parallel deletes queue past the provider's default 30m
  timeout. Deleting the *server* cascades to every child — so
  `az postgres flexible-server delete -g rg-dev-data -n <name> --yes`, then
  re-run the destroy and it no-ops. See `docs/PROVISIONING_PLAN.md` §15.
- **A failed module aborts `make destroy` entirely**. The loop runs under
  `set -e`; everything below the failing module is left untouched. The loop is
  idempotent and resumable — fix the module, re-run `make destroy`.
- **A `VERSION` bump makes every module show a pending tag diff**. Each module
  root stamps `release = local.release` (read from `VERSION`) into `var.tags`,
  so right after `make release-minor`, `terraform plan` reports a `~ tags`
  update on every resource in all twelve modules. That is the intended drift
  signal — code at the new release, Azure still labelled with the old one —
  not a bug. It clears on the next `make apply`. Tag changes are in-place
  updates in `azurerm`; a version bump never recreates a resource.
- **`make validate` breaks `terraform output`**. Validate inits with
  `-backend=false`, leaving every module's `.terraform/` pointed at an empty
  local backend. Any later `terraform output` returns nothing until the
  directory is re-init'd against the azurerm backend. `.terraform/terraform.tfstate`
  is present only when a directory is init'd against the real backend — use it
  to tell the two states apart.

## When helping the user

- Check `docs/PROVISIONING_PLAN.md` first for any decision that spans
  modules (naming, ordering, RG assignment, auth model).
- Match the style of `terraform/bootstrap-backend/` for new module code —
  extensive block comments explaining "why", not just "what".
- User runs all `terraform` commands themselves. Do not `terraform apply`
  or `terraform destroy` from an agent session.
