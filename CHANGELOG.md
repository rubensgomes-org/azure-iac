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

- **`sonar.branch.name=main` pinned in `sonar-project.properties`.** Without it
  the v0.3.0 release run failed at the quality-gate step and published nothing.
  `release.yml` is triggered by a tag push, so `GITHUB_REF` is
  `refs/tags/vX.Y.Z`; the scanner auto-detects GitHub Actions, converts that
  ref into a branch, and submits the analysis as a SHORT-lived branch named
  `refs/tags/v0.3.0`. The submit succeeds, and the subsequent
  `api/qualitygates/project_status?analysisId=...` returns 403 because
  short-lived branch gate status is not readable on this plan. The scanner
  reports that as *"Not authorized or project not found ... check the
  'SONAR_TOKEN' environment variable"*, which points at a token problem that
  does not exist — the 403 reproduces anonymously, and `api/ce/task` in the
  same run returned 200. It also left a junk `refs/tags/v0.3.0` short-lived
  branch in the SonarCloud project.

  This is why a local `make sonar` passed while CI failed on identical config:
  locally there is no CI auto-detection, so the analysis goes to `main`.

  Pinning lives in the properties file rather than the workflow because this
  repo has no branch/PR flow — work lands on `main` and a release is a tagged
  commit on `main` — so the tag always points at main's tip, and it keeps
  scanner config in the single place CI and `make sonar` both read.

  **v0.3.0 remains tagged with no GitHub Release behind it.** Per RELEASING.md
  a published tag is not moved, so this ships as v0.3.1.

## [0.3.0] - 2026-08-25

### Added

- **SonarCloud quality gate in `release.yml`.** A new step runs the scanner
  before the GitHub Release is published and **fails the run if the quality
  gate is red**, so a release can never publish over failing static analysis.
  It sits after `make validate` and before the release-notes/publish steps —
  the slowest gate last, but still strictly ahead of anything user-visible.
  A preceding step verifies `SONAR_TOKEN` is present and names it if not,
  rather than letting the scanner die on an opaque 401 minutes later. The
  scan step is deliberately **not** guarded with `if: env.SONAR_TOKEN != ''`,
  which would silently skip the gate exactly when it is misconfigured.
- `sonar-project.properties` (added in this release) is the single source of
  scanner config. `release.yml` and `make sonar` both read it and pass no
  arguments of their own, so CI and local cannot drift. Two additions to the
  file as authored:
  - `sonar.exclusions=**/.terraform/**,**/.scannerwork/**` — `make validate`
    runs first and leaves a `.terraform/modules/` copy of every local module's
    `.tf` files; without this `sonar.sources=.` indexes both copies, doubling
    ncloc and raising every finding twice.
  - five `sonar.issue.ignore.multicriteria` entries, each with its rationale
    in a comment beside it. `e1` suppresses `githubactions:S7637` (pin actions
    to a full commit SHA) across `.github/workflows/*.yml` — this repo pins
    major version tags on purpose, and without this the scan action's own
    `@v8` pin would fail the very gate it adds. `e2`–`e4` suppress
    `terraform:S6378` (missing `identity` block) on the two storage accounts
    and the registry, which are the *targets* of the shared UAMI's auth rather
    than callers of anything (PROVISIONING_PLAN.md §12). `e5` suppresses
    `terraform:S6382` (client certificate mode) on container-app ingress.

    All of these are suppressed **in-repo rather than marked Accepted in the
    SonarCloud UI**, so every exemption is greppable, diff-visible, and
    reasoned in place instead of living in a web console. `e2`–`e5` are pinned
    to exact file paths, not globs, so a new module that omits an identity
    block still raises the finding.
- `make sonar` — runs the identical scan locally via the official scanner
  image (needs Docker and `SONAR_TOKEN`). `release.yml` fires on a tag that is
  *already pushed* and RELEASING.md forbids moving a published tag, so a red
  gate found in CI costs a whole patch release. This finds it while the tag is
  still just a number in `VERSION`.
- `make sonar` passes `safe.directory` into the container through
  `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0`. Without it the
  scanner container (uid 1000) is refused by git on the bind-mounted tree
  (owned by the host user) with *detected dubious ownership*, the SCM publisher
  drops off the native blame path onto its own history walk, and the run
  appears to hang at "SCM Publisher N source files to be analyzed". With it,
  143 files blame in about nine seconds. CI never hit this — it runs natively
  on Linux against its own checkout.
- `timeout-minutes: 20` on the `release` job. It had no ceiling; the new step
  blocks waiting on SonarCloud, which is exactly the shape of hang a ceiling
  exists for.
- `.scannerwork/` added to `.gitignore`. Not cosmetic: `make release-check`
  fails on a dirty tree, so without it a local `make sonar` followed by
  `make release-patch` aborts the bump for a reason that looks unrelated.

### Changed

### Fixed

- **Script-injection hardening across all four Azure-touching workflows**
  (Sonar `githubactions:S7630`, 9 findings rated BLOCKER). A
  `${{ ... }}` expression written inside a `run:` body is substituted as raw
  text before the shell parses the script, so a value containing a quote or
  `$(...)` executes on the runner. Every occurrence is now bound to an `env:`
  key — safe, because the shell only ever sees a variable — and referenced as
  `"$VAR"`. Comparison logic is unchanged everywhere; only how the values
  arrive is:
  - `acr-create.yml` — job-level `ENV_NAME`, used by the three `make ENV=` steps.
  - `acr-destroy.yml` — job-level `ENV_NAME` for four sites, plus step-level
    `ACTOR` / `TYPED_ACR` / `TYPED_CONFIRM` in the SAFEGUARD step.
  - `tf-bootstrap-destroy.yml` — the same class in its type-to-confirm guard
    (five values, ten occurrences). Sonar did not flag these, but they are the
    identical pattern in the workflow that destroys the state backend, and
    they were the worst form of it: `${{ ... }}` pasted directly into `[ ... ]`
    tests and one entirely unquoted `echo`.

  The affected steps were the guards standing in front of two destroys, with
  credentials already in scope — which is what made this worth fixing rather
  than suppressing. CLAUDE.md now carries the rule so it does not regress.
- `release.yml` header said "All three workflows in this directory pin the same
  build"; there are five.

## [0.2.0] - 2026-08-25

### Added

- `acr-destroy.yml` now also accepts **`workflow_call`**, so another repository
  can tear the registry down as a step in its own pipeline. Every existing
  guard applies unchanged on that path: the `ALLOWED_ACTOR` allowlist (on a
  called run `github.actor` is whoever triggered the *caller's* run, so a
  bot-, schedule-, or third-party-triggered upstream run is denied), the typed
  `DESTROY ACR <name>` phrase, and the plan-scope assertion. `acr_name` and
  `confirm` are declared with **no defaults** on the reusable path — only the
  dispatch form prefills them — so a `uses:` line cannot delete a registry by
  accident. The job keeps `environment: AZURE`, which for a reusable workflow
  resolves in the caller's repo: a calling repository must define that
  Environment itself, which is the point. Its four `workflow_call` secrets are
  therefore `required: false` — a caller may pass them or let its `AZURE`
  Environment supply them, and the existing fail-fast step catches the case where neither happened.

### Changed

- **Workflow files renamed** to a `<subject>-<verb>.yml` shape so each
  subject's pair sorts together in the directory listing. No behaviour change,
  but any external `uses:` reference must be updated:
  - `provision-acr.yml` → **`acr-create.yml`**
  - `destroy-acr.yml` → **`acr-destroy.yml`**
  - `terraform-bootstrap-apply.yml` → **`tf-bootstrap-create.yml`**
  - `terraform-bootstrap-destroy.yml` → **`tf-bootstrap-destroy.yml`**
- `acr-destroy.yml`'s Actions-sidebar name is now **ACR Destroy (reusable)**
  (was "ACR Destroy (manual)"), matching its new trigger set.
- The shared ACR concurrency group is now `acr-lifecycle-<env>` (was
  `provision-acr-<env>`), changed in `acr-create.yml` and `acr-destroy.yml`
  together. The string is deliberately lifecycle-shaped rather than
  verb-shaped: a group only serialises runs that name it identically, and what
  must never overlap a destroy is a create of the same modules.
- README.md, CLAUDE.md, and PROVISION_ACR.md updated for the new filenames,
  the reusable-destroy path, and the caller-side `AZURE` Environment
  requirement.
- `docs/PROVISIONING_PLAN.md` §10 and §16 now describe five workflows rather
  than three, name them, and record the `terraform_wrapper: false` requirement
  alongside the shared `terraform_version` pin.
- `docs/PROJECT_SUMMARY.md` gained the `.github/workflows/`, `PROVISION_ACR.md`
  and `RELEASING.md` entries its repo-layout list was missing, plus a short
  note on how releases work.

### Fixed

- **Three documents disagreed about what is actually applied in Azure.**
  `docs/PROVISIONING_PLAN.md` → Progress and `docs/PROJECT_SUMMARY.md` →
  Status both still described the 2026-07-26 estate ("everything except module
  11 is live"), while CLAUDE.md carried the verified 2026-08-24 state (module
  01 only; the five resource groups exist and are empty; every state key but
  `resource-groups/` is an empty shell). Both are now aligned with CLAUDE.md,
  and both carry the `az` commands to re-check rather than trust the note.
- `RELEASING.md` and CLAUDE.md both still claimed **"no release has been cut
  yet"** with `VERSION` at `0.0.1` and `git tag -l` empty — untrue since
  `v0.0.1` shipped. Both now point at `make version` as the authoritative
  value instead of restating it.
- `RELEASING.md`'s "undoing a release" snippet hardcoded `git tag -d v0.1.1`;
  it now reads `VERSION`, and says why the tag must be deleted before the
  `git reset`.
- `RELEASING.md` described `make release-tag` as "not the path to the first
  release", which stopped being the useful framing once the first release
  shipped. It now says what the target is actually for: recovering a lost tag
  on an already-committed bump.

## [0.1.1] - 2026-08-24

### Added

### Changed

- Both ACR workflows renamed in the Actions sidebar so they sort together:
  `provision-acr.yml` is now **ACR Create (reusable)** (was "Provision ACR
  (reusable)") and `destroy-acr.yml` is now **ACR Destroy (manual)** (was
  "Destroy ACR (manual)", shipped in 0.1.0). Filenames and behaviour are
  unchanged; nothing in the repo keys off a workflow's `name:`.

### Fixed

## [0.1.0] - 2026-08-24

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
