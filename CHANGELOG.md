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

- `.github/workflows/destroy-acr.yml` (**Destroy ACR (manual)**) — manual,
  type-to-confirm workflow that destroys module 06 and nothing else: the
  container registry and every repository, tag, and manifest inside it. The
  five resource groups (module 01) and the shared UAMI (module 04) are
  explicitly preserved, and a guard step reads the destroy plan as JSON and
  aborts the run if it proposes deleting anything other than
  `azurerm_container_registry` / `azurerm_role_assignment`. Binds the `AZURE`
  GitHub Environment, like the bootstrap-destroy workflow.
- `make plan-destroy-<name>` — per-module `terraform plan -destroy -out=tfplan`,
  generated for all twelve modules by the existing target factory. Preview
  only; nothing consumes the artifact.

### Changed

### Fixed

## [0.0.3] - 2026-08-24

### Added

### Changed

- Workflow display names shortened for the Actions sidebar:
  `terraform-bootstrap-apply.yml` is now **TF Bootstrap Create** (was
  "Terraform Bootstrap Backend - APPLY (manual)") and
  `terraform-bootstrap-destroy.yml` is now **TF Bootstrap Destroy**. Filenames
  and behaviour are unchanged; nothing keys off a workflow's `name:`.

### Fixed

## [0.0.2] - 2026-08-24

### Added

### Changed

### Fixed

- `release.yml` pinned `actions/checkout@v4` and
  `hashicorp/setup-terraform@v3`, both of which target the deprecated Node.js
  20 runtime — GitHub force-ran them on Node.js 24 and annotated the `v0.0.1`
  release run. Bumped to `@v7` and `@v4`, matching the other three workflows.
  No infra impact: the release workflow validates and publishes, and holds no
  Azure credentials.

## [0.0.1] - 2026-08-24

Baseline for the first release. The repository was recreated from scratch, so
there is no preceding tag or history to diff against — this section describes
what the estate *is*, not what changed.

### Added

**Terraform estate**

- Twelve module roots under `terraform/envs/dev/` (`01-resource-groups`
  through `12-monitoring`), each owning its own state key in the shared
  azurerm backend, with the numeric prefix encoding dependency order.
- Twelve matching reusable child modules under `terraform/modules/`. No
  state, no backend blocks — provider configuration belongs to the caller.
- `terraform/bootstrap-backend/` — the state backend itself (`rg-tfstate`,
  `sttfstaterubens01`, and the `tfstate` container), whose own state lives in
  the container it provisions.
- `terraform/envs/dev/env.tfvars` and `backend.hcl` — shared per-environment
  inputs and backend configuration, passed at `init`/`plan` time.

**Azure resources provisioned**

- Five lifecycle-aligned resource groups (`platform`, `network`, `data`,
  `app`, `observability`), a VNet with delegated subnets, Log Analytics and
  Application Insights, a shared User-Assigned Managed Identity, Key Vault,
  Container Registry, Storage, Service Bus, PostgreSQL Flexible Server, a
  Container App Environment, Container Apps, and diagnostic settings. APIM is
  deferred to a second iteration.
- Passwordless runtime authentication for every application through a single
  shared UAMI, across PostgreSQL, Blob Storage, Service Bus, Key Vault, and
  ACR. No connection strings, no registry admin user, no application secrets.

**Naming**

- The container registry is named **explicitly** (`rubensdevacr` in dev) via
  the `acr_name` input on `modules/acr`, set in
  `terraform/envs/dev/06-acr/terraform.tfvars`. It deliberately departs from
  the `<random>`-suffixed convention used by `kv-`, `st-`, `sb-`, `log-`, and
  `psql-`: the registry name is typed constantly — image tags, `docker push`,
  `az acr`, `apps_image_map` — so it must be memorable and must survive a
  destroy+recreate. Trade-off: ACR names are globally unique across Azure, so
  a new environment must verify availability with `az acr check-name` before
  setting one; there is no random suffix to fall back on.

**Automation**

- Root `Makefile` — per-module `init`/`plan`/`apply`/`destroy` targets,
  whole-estate `apply`/`destroy`/`reprovision`, plus `purge-orphans`, `fmt`,
  and `validate`. Per-module targets deliberately do no dependency
  resolution; ordering lives in the whole-estate loops.
- `.github/workflows/provision-acr.yml` — reusable workflow (`workflow_call`
  + `workflow_dispatch`) that applies modules 01 → 04 → 06 through the
  Makefile and publishes `acr_name` / `acr_login_server` as outputs, so an
  application pipeline can gate its image push on the registry existing.
  First consumer: `rubensgomes-org/spring-blueprint`.
- `.github/workflows/terraform-bootstrap-apply.yml` and
  `terraform-bootstrap-destroy.yml` — manual (`workflow_dispatch`) lifecycle
  for the state backend, bound to the `AZURE` GitHub Environment, sharing the
  `.github/actions/import-state` composite action.
- All four workflows pin `terraform_version: "1.15.8"` and
  `terraform_wrapper: false`. The pin must satisfy the
  `required_version = "~> 1.15"` declared in every `versions.tf`; the wrapper
  is disabled because it intercepts stdout and would break
  `terraform output -raw`.

**Release tooling**

- `VERSION`, this changelog, `RELEASING.md`, the `make release-*` targets, and
  `.github/workflows/release.yml`, which fires on `v*.*.*` and refuses to
  publish unless the tag, `VERSION`, and a `CHANGELOG.md` section all agree.
  It holds no Azure credentials and deploys nothing.
- A computed `release` tag on every Azure resource, read from `VERSION` on
  disk by each module root's `locals.tf` rather than passed as `-var`, so a
  bare `terraform apply` stamps the same value as `make apply`.

**Documentation**

- `docs/PROVISIONING_PLAN.md` — the authoritative plan: dependency order, RG
  partitioning, naming conventions, the passwordless auth model, §15 complete
  teardown, and §16 release and versioning.
- `PROVISION_ACR.md` — standalone runbook for provisioning and destroying
  only the ACR (modules 01 → 04 → 06), covering the Make commands,
  verification, image push, cost, and the safety notes that apply when
  `apply-`/`destroy-` targets run under `-auto-approve`.
- `CLAUDE.md`, `README.md`, `terraform/INITIAL_SETUP.md`, and a README in
  every module and module root.
