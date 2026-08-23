# Changelog

All notable changes to this project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/) with **infra-impact
semantics** — see [RELEASING.md](RELEASING.md) for what MAJOR / MINOR / PATCH
mean in an infrastructure-as-code repo.

Add entries under `[Unreleased]` as you work. Do not edit the version headings
by hand: `make release-<level>` renames `[Unreleased]` to the new version and
re-seeds an empty `[Unreleased]` block above it.

`[Unreleased]` is for *changes since the last release only*. Outstanding
planned work (D1–D4) lives in `docs/PROVISIONING_PLAN.md` → Deferred work, not
here.

## [Unreleased]

### Added

### Changed

### Fixed

## [0.1.1] - 2026-08-01

### Added

### Changed

### Fixed

- Bootstrap workflows pinned `terraform_version: "1.14.3"`, which does not
  satisfy the `required_version = "~> 1.15"` declared in every `versions.tf`
  in the repo. Both `terraform-bootstrap-apply.yml` and
  `terraform-bootstrap-destroy.yml` now pin `1.15.8`, matching `release.yml`.
  As written they would have failed `terraform init`.

## [0.1.0] - 2026-08-01

Baseline release. Summarises the state of the repo at the point release
tooling was introduced; it is not a reconstruction of the preceding 45
commits.

### Added

- Twelve Terraform module roots under `terraform/envs/dev/`
  (`01-resource-groups` through `12-monitoring`), each with its own state key
  in the shared azurerm backend, and twelve matching reusable child modules
  under `terraform/modules/`.
- `terraform/bootstrap-backend/` — the state backend (`rg-tfstate`,
  `sttfstaterubens01`, `tfstate` container) plus the two manual GitHub
  workflows that apply and destroy it.
- Passwordless runtime authentication for all applications via a single shared
  User-Assigned Managed Identity across PostgreSQL, Blob Storage, Service Bus,
  Key Vault, and ACR.
- Root `Makefile` — per-module `init`/`plan`/`apply`/`destroy` targets,
  whole-estate `apply`/`destroy`/`reprovision`, `purge-orphans`, `fmt`,
  `validate`.
- `docs/PROVISIONING_PLAN.md` — the authoritative plan, including §15 complete
  teardown and §16 release and versioning.
- Release tooling: `VERSION`, this changelog, `RELEASING.md`, the
  `make release-*` targets, and the `release.yml` tag-push workflow.
- A computed `release` tag on every Azure resource, sourced from `VERSION`.
