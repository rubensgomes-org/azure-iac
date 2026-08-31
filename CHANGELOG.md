# Changelog

All notable changes to this project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/) with **infra-impact
semantics** — see [RELEASING.md](RELEASING.md) for what MAJOR / MINOR / PATCH
mean in an infrastructure-as-code repo.

Add entries under `[Unreleased]` as you work. Do not edit the version headings
by hand: `make release-<level>` renames `[Unreleased]` to the new version and
re-seeds an empty `[Unreleased]` block above it.

`[Unreleased]` is for *changes since the last release only*.

This changelog is the **only** place in the repo that records dated history or
deployment state. Every other document — `CLAUDE.md`, `README.md`,
`docs/PROVISIONING_PLAN.md`, `docs/PROJECT_SUMMARY.md`, the module READMEs and
the `bootstrap-backend/` runbooks — describes how to provision, never what is
currently provisioned. Keep it that way: status notes rot, and a reader who
trusts one plans from a false premise.

## [Unreleased]

### Added

### Changed

### Fixed

## [0.5.0] - 2026-08-31

### Changed

- **`owner` and `createdBy` tags on every taggable resource.** `owner` moves
  from `rubens` to `rubens.s.gomes@gmail.com`, and a new
  `createdBy = "terraform"` is added alongside the existing `managedBy`, in
  camelCase to match the surrounding keys. Both source maps
  were edited: `terraform/envs/dev/env.tfvars` (which reaches all twelve estate
  modules through the existing `merge(var.tags, { release = local.release })`
  call site in each root) and `terraform/bootstrap-backend/variables.tf`'s
  `tags` default (which is on a separate path and is not fed by `env.tfvars`).
  No module code changed — every taggable resource in the repo already passed
  `var.tags` through, so the two source maps were the only edits needed.

  The backend deliberately gets **no `environment` key**: it is
  subscription-level shared infrastructure spanning every environment. The
  estate's `environment` tag is unchanged and still tracks the env directory.
  `managedBy` and `createdBy` intentionally carry the same value and are both
  documented as non-duplicates so neither is later "cleaned up".

  Types that cannot carry tags are unaffected — role assignments, subnets and
  their NSG associations, diagnostic settings, PostgreSQL databases/firewall
  rules/AD administrator, Service Bus queues, storage containers and the
  management lock. Tag updates are in-place in `azurerm`; nothing is recreated.

### Added

- **`terraform/bootstrap-backend/TF_DESTROY.md`** — runbook for destroying the
  Terraform state backend. Covers why the teardown needs the local-state
  migration first (the module stores its own state in the container it
  manages), the four managed resources involved, the verification step that
  catches a silent no-op destroy against an empty state, post-destroy checks,
  and the gotchas. Written as procedure only: it names resources by their
  `terraform.tfvars` keys rather than by literal name, and asserts nothing
  about what happens to exist in the subscription, so it does not go stale.

### Changed

- **Documentation no longer records deployment state.** `CHANGELOG.md` is now
  the only place in the repo that carries dated history or status; every other
  document describes how to provision, never what is currently provisioned.
  Removed from `docs/PROVISIONING_PLAN.md`: the `Progress` section, the
  `Deferred work` section (D1–D4), the authoring-time Context snapshot, and
  roughly sixty lines of embedded status markers, event logs and dated
  parentheticals across §2, §6, §11, §12, §12a, §14, §15 and §16 — 1718 lines
  down to 1540. Durable content buried in the removed sections was rescued
  first: the provisioning-order rules and the *Unsupported attribute* failure
  mode into §4, the fixed ACR name rationale into §7, the Makefile target
  naming into §10, module 09's Entra and tooling prerequisites into §13.09, and
  the state-blob verification commands with the `--auth-mode key` explanation
  into §15. Time-bound rationale was rewritten as present-tense rules rather
  than deleted, so the `location`-is-ForceNew warning and the region
  offer-restriction check survive without the version history around them.
  `CLAUDE.md`'s `Project status` section became `Provisioning order`;
  `docs/PROJECT_SUMMARY.md`'s `Status` section became `Region`, `Provisioning
  order`, `Branching` and `Releases`. `README.md`, `RELEASING.md`, the module 09
  and 11 READMEs, and `acr-destroy.yml`'s dated comment were corrected to
  match. No Terraform resource definitions changed.

- **`main-verify.yml` is now `workflow_dispatch`-only.** It previously ran on
  every push to `main`. **Nothing verifies `main` automatically any more** — a
  commit that breaks `fmt -check`, `make validate` or the SonarCloud gate goes
  unnoticed until the workflow is dispatched by hand or a release tag is
  pushed, at which point `release.yml` runs the same three checks. Two
  consequences worth planning around: `make fmt` and `make validate` before
  committing is now the only gate rather than a habit, and a red quality gate
  at tag time is likelier than it was, since the tag push is often the first
  analysis of the release commit — dispatch the workflow before cutting a
  release. A side effect worth knowing: the mirrored copy in the work repo no
  longer fires on a mirror push, so that repo stops producing failed runs.
  `README.md`, `RELEASING.md`, `CLAUDE.md`, `docs/PROJECT_SUMMARY.md` and
  `docs/PROVISIONING_PLAN.md` updated accordingly.

- **`main-verify.yml`'s `sonar` job is opt-in and skipped by default.** The
  dispatch form carries a `run_sonar` boolean input defaulting to `false`, and
  the job's `if: ${{ inputs.run_sonar }}` skips it otherwise, so a bare
  dispatch runs only `terraform` and `workflows`. The scan is the slow part of
  the workflow, the only part needing a secret or reaching a third party, and
  the only part that publishes anything — it overwrites main's quality gate
  status — so it should not be a tax on every "did I break `fmt`?" run. Pass
  `-f run_sonar=true` to include it; most usefully before pushing a release
  tag, since `release.yml` runs the same scan only after the tag exists. A
  skipped job reports as *skipped*, never as a pass, so it cannot be mistaken
  for a green gate. `README.md`, `RELEASING.md`, `CLAUDE.md`,
  `docs/PROJECT_SUMMARY.md`, `docs/PROVISIONING_PLAN.md` and `release.yml`'s
  header updated to show the flag wherever they tell you to dispatch for a
  scan.

- **`main-verify.yml`'s `sonar` job refuses to run off `main`.** A consequence
  of the trigger change: the `workflow_dispatch` form offers a branch selector,
  and `sonar-project.properties` pins `sonar.branch.name=main` while every
  caller passes the scanner no arguments — so a run started from another branch
  would publish that branch's code as main's analysis. A step 0 guard fails the
  job unless `github.ref` is `refs/heads/main`, mirroring `make sonar`'s
  existing refusal. The `terraform` and `workflows` jobs are unguarded: they
  publish nothing, so running them from a branch is harmless.

- **The state backend has been destroyed.** `rg-tfstate`, `sttfstaterubens01`,
  the `tfstate` container and all twelve module state blobs were removed on
  2026-08-31 via the procedure now documented in `TF_DESTROY.md`. The estate is
  at zero *and* has no backend, so a rebuild starts with the two-pass bootstrap
  rather than with `make apply`. Terraform code is unchanged; no module was
  edited.

### Removed

- **`.github/workflows/tf-bootstrap-destroy.yml`.** It ran `terraform init`
  against the azurerm backend and then `terraform destroy -auto-approve`,
  deleting the Storage Account that held the state it was writing to — the
  exact sequence `bootstrap-backend/backend.tf` forbids. Its final
  `upload-artifact` of `errored.tfstate` (a file Terraform writes only when it
  fails to persist state) showed the failure was anticipated; that step also
  pointed at the workspace root while Terraform ran in
  `terraform/bootstrap-backend`, so it captured nothing. A partial failure
  would have left orphaned resources with no state and no way to re-run, since
  the next `init` needs the account just deleted. It had never been run.
  Destroying the backend is now a documented manual procedure
  (`TF_DESTROY.md`).

- **`.github/workflows/tf-bootstrap-create.yml`.** Same `init`-first structure,
  so it could not bootstrap a backend that did not exist yet — its own step 5
  comment said so ("the azurerm backend cannot init against a Storage Account
  that has not been created"). That left it able only to re-apply drift on a
  four-resource module, in a solo repo whose owner has local `ARM_*`. The
  bootstrap is also inherently two-pass and interactive: pass 2 is
  `terraform init -migrate-state`, which prompts, and CI can only get past that
  with `-force-copy` — turning the one irreversible state-migration decision
  into an unattended flag. It had never been run. Creating the backend is a
  documented manual procedure (`terraform/bootstrap-backend/README.md`).

- **`.github/actions/import-state/`.** Orphaned by the two removals above, and
  broken on its own terms: its premise ("Terraform is using the local backend")
  was false because `backend.tf` hardcodes an azurerm backend, so its three
  imports always no-opped via their `terraform state show` guards. It also never
  imported `azurerm_role_assignment.state_blob_contributor`, so the local-state
  model it was written for was only ever half-built. `.github/actions/` is now
  empty and gone.

  Net effect: the state backend has no CI in either direction, which matches
  what it is — a one-time, one-way, hand-operated foundation. Workflow count is
  five; the `terraform_version` bump list is four.

### Fixed

## [0.4.7] - 2026-08-30

### Added

### Changed

- **The Terraform state backend region is now `centralus`, matching the
  estate.** `terraform/bootstrap-backend/terraform.tfvars` and the `location`
  default in its `variables.tf` moved from `eastus` to `centralus`, so the
  bootstrap module describes the region `rg-tfstate` is actually in. The
  v0.4.2 entry below documented the `eastus` backend as a deliberate
  exception; the RG was subsequently recreated in `centralus`, and the code
  is aligned to that rather than moved back. Documentation-and-tfvars only —
  no state blob was migrated, and the change is cosmetic: the azurerm backend
  addresses state by resource group + storage account + container name and
  `envs/dev/backend.hcl` carries no region field, so a state blob's location
  has never affected anything.

  A warning went in alongside it, in `terraform.tfvars` and
  `docs/PROVISIONING_PLAN.md` §15: `location` is ForceNew on
  `azurerm_resource_group`, so editing it against a backend that holds live
  state plans a DESTROY + CREATE of `rg-tfstate` and takes every state blob
  with it. Migrate the blobs out first.

  Corresponding notes updated in `CLAUDE.md`, `docs/PROVISIONING_PLAN.md`
  (region note + §15 exception paragraph + survivor table),
  `docs/PROJECT_SUMMARY.md`, and the two superseded `az` recipes in
  `terraform/bootstrap-backend/INITIAL_SETUP.md`.

### Fixed

## [0.4.6] - 2026-08-30

### Added

- **`storage_account_name` is now a dispatch input on both bootstrap
  workflows** (`tf-bootstrap-create.yml`, `tf-bootstrap-destroy.yml`),
  defaulting to `sttfstaterubens01`. Azure Storage Account names live in a
  global namespace — they must be unique across every tenant in Azure, not just
  this subscription — so the name this project already holds cannot be reused by
  a bootstrap anywhere else, and a hardcoded constant made a fresh backend
  impossible to create or tear down through CI. Resource group and container
  names are only scoped to the subscription and account, so they stay as `env`
  constants.

  The value reaches three places that have to agree, and all three now read one
  environment binding: `terraform init -backend-config="storage_account_name=…"`
  (the literal in `bootstrap-backend/backend.tf` cannot interpolate a variable),
  `-var="storage_account_id=…"` on plan/destroy, and the imports in
  `.github/actions/import-state`. `-var` specifically, not `TF_VAR_` —
  environment variables are Terraform's *lowest*-precedence variable source and
  would lose to the auto-loaded `terraform.tfvars`, so the input would have
  steered the imports while apply still created the name in `tfvars`.

  Both workflows validate the name against `^[a-z0-9]{3,24}$` — the same regex
  as the `storage_account_id` validation in `bootstrap-backend/variables.tf` —
  before Azure login, so a malformed value fails in seconds instead of as an ARM
  400 mid-apply or as an `init` failure that reads like a credentials problem.

  A name that does not exist yet still cannot be created by
  `tf-bootstrap-create.yml` in one pass: the azurerm backend cannot initialise
  against a Storage Account that has not been created. That is the two-pass
  chicken-and-egg already documented at the top of `backend.tf`, and the init
  step now carries a comment pointing at it.

### Changed

- **`tf-bootstrap-destroy.yml`'s safeguard no longer compares the typed storage
  account name against a constant — it enforces double entry instead.** The
  input already existed as an echo checked against
  `EXPECTED_STORAGE_ACCOUNT_NAME`; now that the same input *supplies* that
  value, keeping the comparison would have compared the input to itself — a
  tautology that always passes while still reading like a guard. It is replaced
  by the format check above plus the confirmation phrase, which is now built
  from the typed name, so the account has to be typed identically in two fields
  before Terraform runs. `rg_name` and `container_name` keep their constant
  checks, which caps the blast radius at a Storage Account inside the expected
  bootstrap RG; the `ALLOWED_ACTOR` gate and the `AZURE` Environment binding are
  untouched.

- **Renamed `EXPECTED_STORAGE_ACCOUNT_NAME` to `STORAGE_ACCOUNT_NAME`** across
  both bootstrap workflows and `.github/actions/import-state/action.yml`. The
  prefix now carries meaning rather than decoration: `EXPECTED_` marks a
  constant that an input is validated against (`EXPECTED_RG_NAME`,
  `EXPECTED_CONTAINER_NAME`), and its absence marks the input naming the target
  this run acts on. Both workflows document the split above their `env:` block.

- **`.github/actions/import-state` passes the same `-var` on its post-import
  plan.** Without it that plan would report creating the account named in
  `terraform.tfvars` while the imports immediately above it targeted a different
  one. Both bootstrap workflows set the variable it reads, so the composite
  action needs no new input.

### Fixed

## [0.4.5] - 2026-08-30

### Added

- **`mirror-push.yml` — publish `main` to the private work repository**
  (`rubens-gomes_3CC/azure-iac`, a GitHub Enterprise Managed Users namespace).
  `workflow_dispatch` only: mirroring pushes into a corporate namespace, so
  *when* it happens stays a decision rather than a side effect of committing.
  Force-pushes `main` and nothing else — no tags, no `--mirror` — behind the
  same `ALLOWED_ACTOR` gate the destroy workflows use, plus a check that the
  dispatch ran from `main` (the Actions branch selector accepts any branch, and
  whatever it checks out is what would be pushed). Verifies afterwards that the
  mirror's `main` is at this commit, since `git push` also exits 0 for a push a
  server-side rule quietly rewrote.

  Its one secret is a repo-level `WORK_GITHUB_PAT`; it touches no Azure and runs
  no Terraform, so it carries no `terraform_version` pin. README.md →
  *Mirroring to the work repository* covers the EMU token requirements — in
  particular that the PAT needs `Workflows: Read and write` as well as
  `Contents`, because the mirrored commits touch `.github/workflows/`.

### Changed

### Fixed

## [0.4.4] - 2026-08-30

### Added

### Changed

### Fixed

- **Corrected workflow counts that the `pr-verify.yml` → `main-verify.yml`
  rename left stale.** `acr-create.yml` and `docs/PROVISIONING_PLAN.md` both
  said "five workflows"; there are six. `release.yml`'s timeout comment claimed
  "the other four workflows in this directory carry" one — only three do — so
  the count is dropped rather than corrected, since it rots on every rename.

- **`RELEASING.md` no longer illustrates the `release` tag drift with `0.1.0`
  / `0.2.0`**, versions the repo left behind at v0.2.0. The two consequences are
  now stated without hardcoded numbers.

## [0.4.3] - 2026-08-29

### Added

### Changed

- **Moved all development and maintenance to a single `main` branch.** The
  repo is trunk-based again: `main` is the only branch, every change is
  committed straight to it, and there are no feature branches, pull requests,
  or branch protection. The PR-only model introduced in 0.4.0 bought review
  that a single maintainer cannot supply, and cost a two-phase release.
  `.github/pull_request_template.md` is deleted.

- **`pr-verify.yml` → `main-verify.yml`, triggered by `push` to `main`.** Same
  three jobs (`terraform`, `workflows`, `sonar`) and the same checks; the
  concurrency key moves from the PR number to `github.ref`, and the `sonar`
  job drops `pull-requests: write` since there is no diff to decorate. It
  reports *after* the push and is deliberately not a required status check — a
  check that only fires on a push cannot gate that push. `release.yml` still
  re-runs all three at tag time, where a red gate genuinely blocks.

- **`make release-patch|minor|major` restored as the whole release.** Each
  bumps `VERSION`, rolls `[Unreleased]` into a dated section, commits *and*
  creates the annotated tag, all locally; `make release-push` then pushes
  `main` and the tag. `make release-prep-*` and the `RELEASE_BRANCH_MODE`
  switch are removed — every release target now simply requires `main`. Until
  `release-push`, `git tag -d v$(cat VERSION) && git reset --hard HEAD~1`
  undoes a release completely, which the two-phase model could not offer once
  the release PR had merged.

- **`sonar.branch.name=main` pinned in `sonar-project.properties` again.** With
  no pull requests there is one correct value, so all three callers
  (`main-verify.yml`, `release.yml`, `make sonar`) now pass the scanner no
  arguments at all and cannot drift. This restores the pre-0.4.0 arrangement
  and removes the one sanctioned exception to that file's "no scanner
  arguments in the workflow" rule. The pin remains load-bearing for
  `release.yml`, which fires on a tag ref — see `[0.3.1]`.

### Fixed

- `make sonar` no longer told you to open a pull request when run off `main`,
  and `RELEASING.md` no longer claimed `VERSION` was `0.2.0`.

## [0.4.2] - 2026-08-29

### Added

### Changed

- **Estate region moved from `eastus` to `centralus`.** One line —
  `location` in `terraform/envs/dev/env.tfvars` — drives all 12 modules.
  No resource name in this repo embeds the region, so nothing is renamed.

  **Read this before applying on a live estate.** This release is PATCH
  because it was applied against an EMPTY estate (nothing in `envs/dev` was
  provisioned at the time), so `terraform plan` was create-only and no
  resource churned. That is a fact about the estate, not about the change.
  On an already-applied estate the same edit is MAJOR-shaped: `location` is
  ForceNew on every `azurerm` resource, so `plan` shows
  `-/+ destroy and then create` on everything — and because no name changes,
  there is no name diff to warn you. `make apply` runs `-auto-approve`.
  Always `make plan-<module>` first.

- **Removed the module 09 PostgreSQL `eastus2` region override.** PG Flex now
  inherits `centralus` from the shared `env.tfvars` like every other module,
  ending the two-region split. The override existed only because this
  subscription is offer-restricted from provisioning PG Flexible Server in
  `eastus` (`LocationIsOfferRestricted`); `centralus` carries no such
  restriction — verified against
  `az postgres flexible-server list-skus --location centralus`, which reports
  no restriction and offers `Standard_B1ms`, zones `[1,2,3]`, and 32768 MB
  storage. Check any future region the same way *before* editing
  `env.tfvars`; a restricted one brings the override back.

- **The Terraform state backend deliberately stays in `eastus`.**
  `rg-tfstate` / `sttfstaterubens01` were not moved and
  `terraform/envs/dev/backend.hcl` was not touched. The azurerm backend
  addresses state by resource group + storage account + container name and has
  no region field at all, so a state blob's region is independent of where the
  resources it tracks live. Moving it would have meant a new globally-unique
  storage account name and a migration of 13 state blobs, for no benefit.

- **Docs re-anchored on the new region**: `docs/PROVISIONING_PLAN.md` §15's
  "Region caveat" is now "Region: single, no caveat"; the module 09 README's
  `LocationIsOfferRestricted` / `InvalidResourceLocation` troubleshooting keeps
  the failure modes but no longer describes an override that exists; Key Vault
  purge and Container Apps default-domain examples updated. ACR cost figures in
  `PROVISION_ACR.md` were re-fetched from the Azure retail pricing API rather
  than assumed — registry-unit rates are identical in `eastus` and `centralus`,
  so the table is unchanged and now says so.

### Fixed

- **Project status was stale in three places.** `CLAUDE.md`,
  `docs/PROVISIONING_PLAN.md` → Progress, and `docs/PROJECT_SUMMARY.md` →
  Status all claimed module 01-resource-groups was still applied with its five
  resource groups sitting empty. It has since been destroyed: the estate is at
  zero and the resource groups are gone, not empty. All three corrected against
  a live check and re-dated, and the module-01 assumption removed from the "ACR
  only" rebuild chain in each, which now starts with
  `make apply-resource-groups`. Each now also states the estate region and the
  backend's deliberate `eastus` exception, so the next reader does not have to
  infer either.

- **Two module READMEs described an estate that no longer exists**, in ways
  that would have sent a reader down a failing path:
  - `11-container-apps/README.md` claimed "every upstream module listed under
    Prerequisites is still applied, so `make apply-container-apps` on its own
    brings the apps back". All seven upstreams are destroyed; that command now
    fails at plan with *Unsupported attribute*. Replaced with the ordered
    apply chain.
  - `09-postgresql/README.md` opened with a "mid-flight state" resume block
    saying the server, admin binding, firewall rules, and databases were
    applied and the next plan would show "1 to destroy". Nothing is applied and
    there is no state to reconcile. Rewritten around the real starting point;
    the `run_bootstrap = false` gate and the Cloud Shell data-plane step are
    unchanged and still required. Also replaced a hardcoded
    `psql-dev-1f91...` FQDN with the `<hex>` placeholder — `random_id.suffix`
    regenerates on a fresh apply, so that value can never be correct again.

- **`docs/PROVISIONING_PLAN.md` → Deferred work / D1** still reasoned from
  "only module 11 is down". D1 now notes that ACR must be reprovisioned before
  images can be pushed at all, and that a bare `make apply-container-apps`
  cannot work until the upstream chain is applied.

- **`12-monitoring/README.md`** said the estate was "feature-complete pending
  Makefile automation". That automation landed some releases ago.

- **`PROVISION_ACR.md`** said module 01 "is normally already applied" and that
  re-running it is a no-op. With the estate at zero the common case is 5-to-add;
  the sentence now covers both and keeps the idempotence point.

## [0.4.1] - 2026-08-25

### Added

- **README.md gained a "Working on this project" section** — the end-to-end
  steps for both flows, "starting new work" and "cutting a release", as
  numbered command sequences with the non-obvious parts called out: branch
  protection only bites at push time so a forgotten `git switch -c` surfaces
  late; the `[Unreleased]` entry belongs in the same PR; `make sonar` is not
  part of the flow; and the release tag must be created after the merge. A
  pointer to it sits at the top of the README, since a contributor's first
  question is "where do I start" and that answer was previously two thirds of
  the way down the file.

  The `Branching` and `Releases` sections kept their explanations but lost
  their command blocks, which were now a second copy of the same recipe. Two
  copies drift — this repo has spent several releases fixing exactly that.

### Changed

- **`make sonar` dropped from the release recipe.** It existed because
  `release.yml` fires on a tag that is already pushed, so a red quality gate
  cost a whole patch release and there was no earlier gate. v0.4.0 removed that
  premise: `main` is PR-only and `pr-verify.yml` runs the same scan in PR mode,
  so the gate blocks the merge before a tag exists, and `release.yml` scans
  again at tag time. The recipe in `RELEASING.md` is now six steps with no
  local Sonar step.

  The target remains as a fallback for reproducing a CI Sonar failure locally,
  and its documentation now says what it costs: on Apple Silicon the scanner
  image is amd64-only and its SCM publisher blames through JGit rather than the
  git CLI, measured at **minutes** for ~144 files where native `git blame` over
  the same files takes about a second — and worse now that `main` carries merge
  commits for JGit to walk both parents of. `SCM blame is in progress..` means
  it is working, not hung.

  Also corrects a claim in the `sonar` recipe's comment: the `GIT_CONFIG_*`
  `safe.directory` trio fixes the *dubious ownership* failure, which is a hard
  stop with no blame progress at all, but it does not make the step fast. Those
  are two different symptoms and the comment conflated them.

### Fixed

## [0.4.0] - 2026-08-25

### Added

- **`.github/workflows/pr-verify.yml`** — the gate on every pull request into
  `main`, and what branch protection's required checks point at. Until now the
  repo had **no CI on a branch at all**: `fmt -check`, `make validate` and the
  Sonar gate ran only at tag time, inside `release.yml`, long after the point
  where feedback is useful. Three deliberately separate jobs, so one can be
  added to or dropped from the required list without un-gating the others:
  - `terraform` — `terraform fmt -check -recursive` and `make validate`.
  - `workflows` — every workflow and composite action parses as YAML, and no
    GitHub `${{ }}` expression appears inside a `run:` body (Sonar
    `githubactions:S7630`). The second check is instant, needs no token, and
    works on a fork, which is why it is worth duplicating what Sonar catches.
  - `sonar` — SonarCloud analysis in **PR mode**, decorating the diff. Passes
    no branch name; the action detects the pull request itself.
  It holds no Azure credentials, like `release.yml`.
- **`.github/pull_request_template.md`** — checklist led by the `CHANGELOG.md`
  `[Unreleased]` entry, since a release refuses to cut without one and that
  entry is easiest to write while the change is fresh.
- `make release-prep-patch|minor|major` — bump `VERSION`, roll the changelog,
  commit. **No tag.** Runs from a `release/*` branch.

### Changed

- **`main` is now PR-only.** Every commit, releases included, reaches it
  through a pull request whose checks pass. Direct pushes are rejected.
- **Releases are now two phases.** A `release/vX.Y.Z` PR carries the `VERSION`
  bump and changelog roll; the tag is placed on `main` *after* that PR merges,
  by `make release-tag`. This ordering is required, not stylistic: squash-merge
  rewrites the commit SHA, so a tag created before the merge would point at a
  commit `main` never sees. `make release-tag` is consequently promoted from
  escape hatch to the second half of every release.
- `make release-patch|minor|major` **removed.** They bumped, committed and
  tagged in one shot on `main`, which cannot work when `main` is PR-only. They
  now fail with a pointer to the new recipe rather than leaving an unpushable
  tag behind.
- `RELEASE_PRECHECK`'s branch assertion is parameterised: `release-prep-*`
  requires a `release/*` branch, everything else still requires `main`. It also
  now prints the branch it actually found instead of the literal `branch=main`.
- **`sonar.branch.name=main` removed from `sonar-project.properties`.** Added
  only hours earlier to fix the v0.3.0 tag-analysed-as-a-short-lived-branch
  failure, it becomes actively harmful under a PR flow: a global pin would make
  every PR analysis submit the PR's code **as `main`**, overwriting main's
  analysis and handing main a quality gate result for code nobody merged. The
  branch is now supplied per caller — nothing from `pr-verify.yml`,
  `-Dsonar.branch.name=main` from `release.yml` and from `make sonar`. This is
  the one sanctioned exception to that file's "no scanner arguments in the
  workflow" rule, and the file now documents it as such.
- `make sonar` **refuses to run off `main`** and passes the branch explicitly.
  On a feature branch it would publish that branch's code as main's analysis.
- `README.md` gained a Branching section; `RELEASING.md`'s recipe and its
  "Undoing a release" section were rewritten around the two phases (what you
  can undo now depends on whether the release PR has merged). `CLAUDE.md`,
  `docs/PROVISIONING_PLAN.md` §16 and `docs/PROJECT_SUMMARY.md` updated. The
  Terraform CLI pin is now a **six**-workflow invariant.

### Fixed

## [0.3.1] - 2026-08-25

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
- `CLAUDE.md`, `README.md`, `terraform/bootstrap-backend/INITIAL_SETUP.md`, and a README in
  every module and module root.
