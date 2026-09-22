# Changelog

All notable changes to this project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/) with **infra-impact
semantics**: PATCH for in-place tweaks and docs, MINOR for new resources or
modules, MAJOR for anything that destroys, recreates, or renames an existing
resource. `make release-check` prints the same three lines against the current
`VERSION`.

Add entries under `[Unreleased]` as you work. Do not edit the version headings
by hand: `make release-<level>` renames `[Unreleased]` to the new version and
re-seeds an empty `[Unreleased]` block above it.

`[Unreleased]` is for *changes since the last release only*.

This changelog is the **only** place in the repo that records dated history or
deployment state. Every other document — `README.md`,
`docs/MODULES_DEPENDENCY.md`, the module READMEs and the `bootstrap-backend/`
runbooks — describes how to provision, never what is currently provisioned. Keep
it that way: status notes rot, and a reader who trusts one plans from a false
premise.

## [Unreleased]

### Added

### Changed

### Fixed

- `aca-destroy` verification now checks only the apps in `TF_VAR_apps`,
  instead of failing on other repositories' `ca-*-<env>` apps left
  standing in the shared environment. The pre-destroy inventory no longer
  labels those apps as about to be destroyed.

## [0.0.25] - 2026-09-22

### Added

### Changed

### Fixed

- Module 11's `plan-`/`apply-`/`destroy-container-apps` targets now act
  only on the apps named in `TF_VAR_apps`, passing one `-target` per app.
  `azurerm_container_app.app` is `for_each = toset(var.apps)` and each
  app's repository calls the reusable workflows passing only its own app,
  so the unscoped recipes reconciled the whole `for_each` map against a
  partial list: `apply-container-apps` destroyed every app NOT named
  (silently, under `-auto-approve`, from a workflow called "create"), and
  `destroy-container-apps` ignored `TF_VAR_apps` and destroyed every app
  in state. The whole-estate `apply` now refuses to run when state holds
  an app absent from `TF_VAR_apps`; whole-estate `destroy` is unchanged,
  since a full teardown is meant to remove every app.

## [0.0.24] - 2026-09-21

### Added

### Changed

### Removed

- `apps_without_ingress` (added in 0.0.22, documented in 0.0.23):
  every app now gets an `ingress` block again, provisioned identically.
  Non-HTTP apps must ship a listener on `target_port` instead of
  opting out of ingress. Removed from the `container-apps` module,
  the `11-container-apps` root, `aca-create.yml`, and
  `scripts/initvars.sh`.

### Fixed

## [0.0.23] - 2026-09-21

### Added

- `docs/INITIAL_SETUP.md`: documented `TF_VAR_apps_without_ingress` in the
  Terraform (tfvars) Environment Variables section.
- `scripts/initvars.sh`: manages `TF_VAR_APPS_WITHOUT_INGRESS`, defaulting
  to `[]`.

### Changed

### Fixed

## [0.0.22] - 2026-09-21

### Added

- `container-apps` module: `apps_without_ingress` variable (`set(string)`,
  default `[]`). Apps listed get no `ingress` block at all, so Azure
  never injects the default StartUp probe a non-HTTP app (no listener)
  can never pass.

### Changed

- `aca-create.yml`: accepts an `apps_without_ingress` input, falling
  back to the `TF_VAR_apps_without_ingress` repository variable, then
  `[]`. Forwarded to module 11.

### Fixed

## [0.0.21] - 2026-09-20

### Added

### Changed

- `aca-create.yml`: accepts a `TF_VAR_target_port` override from the
  calling repository's Action Variables, defaulting to `80` (the
  quickstart placeholder image's port) when unset.

### Fixed

## [0.0.20] - 2026-09-19

### Added

### Changed

### Fixed

- `aca-create.yml`, `aca-destroy.yml`, `cae-create.yml`, `cae-destroy.yml`,
  `acr-create.yml`, `acr-destroy.yml`: checkout's `ref:` now uses
  `job.workflow_sha` instead of `job.workflow_ref`. The latter is the FULL
  `owner/repo/.github/workflows/file.yml@ref` string, not a bare ref, and
  `actions/checkout` tried to use it as a refspec verbatim, failing with
  "invalid refspec" on every `workflow_call` run.

## [0.0.19] - 2026-09-19

### Added

### Changed

### Fixed

- `aca-create.yml`, `aca-destroy.yml`, `cae-create.yml`, `cae-destroy.yml`,
  `acr-create.yml`, `acr-destroy.yml`: checkout now resolves the reusable
  workflow's own repo/ref via `job.workflow_repository`/`job.workflow_ref`.
  `github.job_workflow_ref` was observed empty on an actual `workflow_call`
  run, so checkout fetched the CALLER's repo instead of this one, and `make`
  failed with "No rule to make target".

## [0.0.18] - 2026-09-19

### Added

- `release.yml`: publish/move a `vX` major-version tag (e.g. `v0`) to the
  release commit after each GitHub Release, so callers can pin
  `@v0` and track the latest `v0.y.z` release.

### Changed

### Fixed

- `aca-create.yml`, `aca-destroy.yml`, `acr-create.yml`, `acr-destroy.yml`,
  `cae-create.yml`, `cae-destroy.yml`: checkout now resolves this repo and
  ref from `github.job_workflow_ref` instead of defaulting to
  `github.repository`/`github.sha`, which resolve to the CALLER's repo on
  `workflow_call` and checked out a repo with no `Makefile`.

## [0.0.17] - 2026-09-19

### Added

- `aca-create.yml`, `aca-destroy.yml`: optional `apps` input on
  `workflow_call`, forwarded to `TF_VAR_apps`. Falls back to the
  `TF_VAR_apps` repository variable when omitted.

### Changed

- All `.github/workflows/*.yml` reflowed to a maximum line width of 80
  columns. No functional changes.

### Fixed

## [0.0.16] - 2026-09-19

### Added

### Changed

- `modules/container-apps`, `roots/11-container-apps`: Container App names
  no longer fold in the `workload` token — `ca-<app>-<env>` (e.g.
  `ca-api-lab`) instead of `ca-<workload><app>-<env>` (e.g.
  `ca-rgomesapi-lab`). `name` is ForceNew, so applying this destroys and
  recreates every existing Container App under its new name. See
  `docs/NAMING.md`'s second exception.

### Fixed

- `aca-destroy.yml`: the pre-destroy inventory and post-destroy
  verification `az containerapp list` filters no longer match on
  `ca-${TF_VAR_workload}`, which would otherwise have silently stopped
  matching any Container App and turned the post-destroy check into a
  false pass.

### Removed

- `modules/container-apps`: the `workload` input variable, now unused.
  `roots/11-container-apps` no longer forwards it; the root variable is
  retained only for `env.tfvars` parity.

## [0.0.15] - 2026-09-18

### Added

### Changed

### Fixed

### Removed

- `modules/container-app-environment`, `roots/10-container-app-environment`:
  the optional `cae_name` override added in `[0.0.14]`. The environment
  name is once again always `cae-<workload>-<env>`.
- `cae-create.yml`/`cae-destroy.yml`: the `TF_VAR_cae_name` handling and
  its pre-apply/pre-destroy state-matching guards.
- `scripts/initvars.sh`: no longer manages `TF_VAR_CAE_NAME`; added to
  `RETIRED_ACTION_VARIABLES` so an existing repository variable gets
  swept on the next delete pass.

## [0.0.14] - 2026-09-18

### Added

- `modules/container-app-environment`, `roots/10-container-app-environment`:
  optional `cae_name` variable to override the environment's resource name.
  Defaults to `cae-<workload>-<env>` when unset/empty, unchanged from before.
- `cae-create.yml`/`cae-destroy.yml`: read the optional `TF_VAR_cae_name`
  repository variable (same pattern as `TF_VAR_workload`), no workflow input.
  `cae-create.yml` gains a pre-apply guard comparing the resolved name
  against Terraform state (name is ForceNew). `cae-destroy.yml` now resolves
  the target name from Terraform state rather than the `workload`/`env`
  formula, cross-checking `TF_VAR_cae_name` against it, so its dependent-apps
  guard and post-destroy verification can't silently run against the wrong
  name.
- `scripts/initvars.sh`: manages `TF_VAR_CAE_NAME`, but only when
  `TF_VAR_cae_name` is exported locally, so an operator who has never used
  it is not forced to invent one. Documented in `docs/INITIAL_SETUP.md`
  as a note, separate from the required Action Variables list.

### Changed

### Fixed

## [0.0.13] - 2026-09-18

### Added

### Changed

- `modules/container-apps`, `roots/11-container-apps`: `ingress_external_enabled`
  now defaults to `false` (internal-only ingress), matching the environment's
  `internal_load_balancer_enabled = true` (module 10). Comments, READMEs,
  outputs, and `aca-create.yml`'s output description updated to describe
  internal-only reachability by default.

### Fixed

- `modules/container-app-environment`, `roots/10-container-app-environment`:
  comments and READMEs still described external ingress as the default even
  though `internal_load_balancer_enabled = true` was already set; corrected
  to match.
- `cae-destroy.yml`: job `timeout-minutes` raised from 15 to 30. Deleting a
  VNet-integrated Container App Environment routinely exceeds 15 minutes
  while Azure tears down the VNet integration, which was canceling the
  destroy job mid-apply.

## [0.0.12] - 2026-09-17

### Added

### Changed

- `scripts/initvars.sh`: rewritten to also manage GitHub Actions
  *secrets* (`AZURE_CLIENT_SECRET`, `SONAR_TOKEN`), not just
  variables. Deletes and recreates both by default; secret values
  are never printed or logged. Added `-o, --delete-only` (delete
  without recreating) and `-n, --dry-run` (print the plan, change
  nothing).
- `docs/INITIAL_SETUP.md`: added `SONAR_TOKEN` to the Action Secrets
  list and updated the `initvars.sh` note for the above.

### Fixed

## [0.0.11] - 2026-09-17

### Added

- `docs/PRICING.md`: cost model for the ACR, private DNS, Container Apps,
  Key Vault, and Log Analytics resources this estate provisions, linked from
  the README.

### Changed

- `sonar-project.properties`: narrowed `sonar.inclusions` to source files
  (`.hcl`, `.json`, `.tf`, `.yml`), excluded `.md` files, and updated
  `sonar.projectKey`.
- `.gitignore`: ignore Sonar scratch/config directories (`.sonar/`,
  `**/.scannerwork/`, `.sonarlint/`).

### Fixed

- `.gitignore` had unresolved, nested merge-conflict markers left over from
  a bad merge; removed the duplicate blocks.

## [0.0.10] - 2026-09-15

### Added

### Changed

### Fixed

- `acr-destroy.yml` and `cae-destroy.yml` now fail fast with a GUARD step if
  module 11's Container Apps still reference the registry or environment
  being destroyed, instead of either succeeding silently (ACR, which Azure
  does not protect) or failing later with an opaque Azure error mid-apply
  (CAE).

## [0.0.9] - 2026-09-15

### Added

- `aca-create.yml`, a reusable workflow that applies modules 01 → 02 → 03 →
  04 → 05 → 06 → 10 → 11 so the Container Apps exist, following
  `cae-create.yml`'s pattern.
- `aca-destroy.yml`, a reusable workflow that destroys module 11 only (the
  Container Apps), following `cae-destroy.yml`'s pattern.

### Changed

### Fixed

## [0.0.8] - 2026-09-15

### Added

### Changed

- `11-container-apps` now depends on `05-key-vault` instead of
  `07-storage`, `08-service-bus`, and `09-postgresql`. Container apps get
  a `KEY_VAULT_URI` env var in place of the removed `POSTGRES_*`,
  `STORAGE_*`, and `SERVICEBUS_*` env vars, and the now-unused `uami_name`
  module input was dropped.
- Updated `07-storage`, `08-service-bus`, and `09-postgresql` (roots,
  child modules, and READMEs) to stop describing `11-container-apps` as
  their consumer, matching the dependency change above.

### Fixed

## [0.0.7] - 2026-09-15

### Added

- `cae-create.yml`, a reusable workflow that applies modules 01 → 02 → 03 →
  10 so a Container App Environment exists, following `acr-create.yml`'s
  pattern.
- `cae-destroy.yml`, a reusable workflow that destroys module 10 only (the
  Container App Environment), following `acr-destroy.yml`'s pattern.

### Changed

### Fixed

## [0.0.6] - 2026-09-15

### Added

### Changed

- `environment_name` is now required (no default) on `acr-create.yml`,
  `acr-destroy.yml`, and `destroy-all.yml`, and a `dev`/`lab` choice dropdown
  on their `workflow_dispatch` triggers.
- `acr_name` is now required (no default) on `acr-create.yml` and
  `acr-destroy.yml`, and a `crrgomesdev01`/`crrgomeslab02` choice dropdown on
  their `workflow_dispatch` triggers.
- `acr-destroy.yml`'s `confirm` input is now a Yes/No choice dropdown on
  `workflow_dispatch` (was a typed `DESTROY ACR <env> <acr_name>` phrase);
  `workflow_call` now expects the literal string `Yes`.

### Fixed

## [0.0.5] - 2026-09-15

### Added

### Changed

### Fixed

- fixes

## [0.0.4] - 2026-09-15

### Added

### Changed

### Fixed

- several fixes

## [0.0.3] - 2026-09-15

### Added

### Changed

### Fixed

- fixed documentation comments

## [0.0.2] - 2026-09-15

### Added

### Changed

### Fixed

- Document dev's registry as `crrgomesdev01` in `06-acr` and `modules/acr`.
  It had been recorded as `crrgomesdev01`, which is lab's registry; the two
  cannot share a name, since ACR names are globally unique across Azure.

## [0.0.1] - 2026-09-14

### Added

- Initial release.

### Changed

### Fixed

### Removed
