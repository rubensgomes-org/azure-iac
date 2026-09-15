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

- Initial release.

### Changed

### Fixed

### Removed
