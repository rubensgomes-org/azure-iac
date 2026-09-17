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
