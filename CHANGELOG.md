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
