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

**Region** is a single `location` in `terraform/envs/dev/env.tfvars` driving all
12 modules, with no per-module overrides.

**The ACR name is fixed**, set in `terraform/envs/dev/06-acr/terraform.tfvars`
rather than generated as `acr<env><random>`. A fixed name survives a destroy and
recreate, which is what makes it safe to hardcode in image tags and in an
application pipeline's push target.

## Where the master plan lives

**`docs/PROVISIONING_PLAN.md`** — dependency order, RG partitioning, naming
conventions, per-module scaffolding, workflow commands, passwordless auth
model, verification checklists. **§15 is the authoritative complete-teardown
procedure** (prereqs, verification, what legitimately survives, removing the
state backend, and the two ways a destroy can silently do nothing).

Always read that file before making infra decisions.

## Provisioning order

**A rebuild starts with the state backend, not with module 01.** Until the
backend exists, every module root's `terraform init
-backend-config=../backend.hcl` targets a Storage Account that is not there, so
`make apply` cannot run at all. The order is:

1. Bootstrap `terraform/bootstrap-backend/` — two passes (apply on local state,
   then `terraform init -migrate-state` once the container exists). See
   `terraform/bootstrap-backend/TF_PROVISION.md`.
2. `terraform init -reconfigure -backend-config=../backend.hcl
   -backend-config="key=<module>/terraform.tfstate"` in each module root.
3. `make apply` from repo root, or module-by-module in numeric order.

Each module's upstreams must be applied first — a root whose
`data.terraform_remote_state` points at an empty state key fails at plan with
*Unsupported attribute*, which does not name the real cause. Minimum chains
worth knowing:

- **ACR only**: `make apply-resource-groups && make apply-managed-identities &&
  make apply-acr` (06 needs 01's platform RG and 04's UAMI for the `AcrPull`
  grant).
- **Container Apps**: 01, 04, 06, 07, 08, 09, 10, then 11.

`make apply` / `make destroy` from repo root drives the whole estate;
per-module `make apply-<short-name>` handles one at a time.


## Release process

This repo is **trunk-based** — `main` is the only branch, and every change,
releases included, is committed straight to it and pushed. There are no feature
branches, no pull requests, and no branch protection. Do not create one unless
the user asks.

Every release is a `MAJOR.MINOR.PATCH` git tag on `main`. Read
**`RELEASING.md`** before touching anything release-related;
`docs/PROVISIONING_PLAN.md` §16 has the design rationale.

- Repo-root **`VERSION`** (bare `MAJOR.MINOR.PATCH`, no `v`) is the single
  source of truth. The tag is `v$(cat VERSION)`; the `CHANGELOG.md` heading and the
  `release` tag on every Azure resource both derive from it.
- Semver is **infra-impact based**: MAJOR = `plan` destroys/recreates or
  renames an existing resource; MINOR = additive; PATCH = in-place only.
  Project stays at `0.x` until D1/D2 close and a full `make apply` from zero
  verifies clean.
- Bumps are **manual and explicit**, and a release is two commands.
  `make release-patch|minor|major` runs **from `main`**: it writes `VERSION`,
  rolls `[Unreleased]` into a dated section, commits, **and creates the
  annotated tag** — all locally. `make release-push` then pushes `main` and the
  tag, in that order, and is the only step that touches the network. Until it
  runs, `git tag -d v$(cat VERSION) && git reset --hard HEAD~1` undoes the whole
  thing. There is no `make release-prep-*` step: because the release commit is
  made directly on `main`, the SHA that is tagged is the SHA that is pushed, so
  the bump and the tag happen together. `make release-tag` tags the current
  `VERSION` without bumping and is an escape hatch only — for when a bump
  committed cleanly but the tag was lost before it was pushed.
  `make version` is the authoritative current value.
- Every module root has a `locals.tf` reading `VERSION` off disk
  (`trimspace(file("${path.root}/../../../../VERSION"))`) and merges
  `release = local.release` into `var.tags`. Read from disk, not passed as
  `-var`, so a bare `terraform apply` typed by hand stamps the same value.
- `.github/workflows/release.yml` fires on `v*.*.*`: checks tag ==
  `VERSION` == a `CHANGELOG.md` section, runs `fmt -check` + `make validate`
  + the **SonarCloud quality gate**, then publishes a GitHub Release.
  **`release.yml` specifically holds no Azure credentials — keep it that
  way.** Its one secret is `SONAR_TOKEN`, which reaches sonarcloud.io and
  cannot touch the subscription; that carve-out does not open the door to
  `ARM_*`. Other workflows in this repo do hold Azure credentials; see the CI
  section below.
- **A red quality gate blocks the release but not the tag.** The scan runs
  after the tag is already pushed, so a failure leaves a tag with no GitHub
  Release. RELEASING.md forbids moving a published tag, so the fix is the next
  patch release. Expect it: nothing scans a commit automatically, so the tag
  push is often the first time SonarCloud sees it. Run `make sonar`, or
  dispatch `main-verify.yml` with `-f run_sonar=true`, before cutting a
  release you care about. The gate
  is also evaluated against SonarCloud's current state, so a quality-profile
  change can turn it red with no commit involved.

## CI — GitHub Actions

Five workflows, three credential models. All Azure-touching workflows get
`ARM_*` from GitHub secrets holding the same `terraform-sp` Service Principal
documented under Auth model. The other two models are `SONAR_TOKEN`, which
reaches sonarcloud.io and nothing else, and `WORK_GITHUB_PAT`, which reaches
one private repository in a work GitHub namespace and nothing else. Neither can
touch the subscription; keep it that way.

**`main-verify.yml` is `workflow_dispatch`-only.** Three deliberately separate
jobs — `terraform` (`fmt -check` + `make validate`), `workflows` (every workflow
file parses; no GitHub expression inside a `run:` body), `sonar` (analysis of
`main`). Separate jobs mean separate check names, so a failure names the area.
It holds no Azure credentials and must stay that way.

**`sonar` is opt-in and off by default.** The dispatch form carries a
`run_sonar` boolean input defaulting to `false`, and the job's
`if: ${{ inputs.run_sonar }}` skips it otherwise. A bare dispatch therefore
runs the two cheap local checks only. The scan is the slow part, the only part
needing a secret or a third party, and the only part that *publishes* anything
— it overwrites main's quality gate status — so it should not be a tax on every
"did I break `fmt`?" run. Turn it on with `-f run_sonar=true`. A skipped job
reports as **skipped**, never as a pass, so it cannot be mistaken for a green
gate. (`type: boolean` means the `inputs` context yields a real boolean, unlike
`github.event.inputs.*` which is always a string — hence no `== 'true'`
comparison.)

**No workflow verifies `main` automatically.** A commit that breaks
`fmt -check`, `make validate` or the Sonar gate stays unnoticed until someone
dispatches this workflow or pushes a release tag, at which point `release.yml`
runs the same three checks. **`make fmt` and `make validate` before committing
is the only gate**, not a belt-and-braces habit.

It cannot be a required status check — a dispatch-only workflow reports against
no push at all.

**The dispatch form's branch selector accepts any ref**, so the `sonar` job
carries a step 0 that fails the run unless `github.ref` is `refs/heads/main`.
`sonar-project.properties` pins `sonar.branch.name=main` and every caller
passes the scanner no arguments, so a run from another branch would publish
that branch's code as main's analysis. This is the CI counterpart of
`make sonar`'s refusal to run off `main`. The `terraform` and `workflows` jobs
are unguarded on purpose: they publish nothing, so running them from a branch
is harmless.

| Workflow | Actions-tab name | Trigger | Touches Azure | Secret source |
| --- | --- | --- | --- | --- |
| `main-verify.yml` | Main Verify | `workflow_dispatch` | **no** | **org**-level `SONAR_TOKEN` (not Azure) |
| `release.yml` | Release (tag push) | tag `v*.*.*` | **no** | **org**-level `SONAR_TOKEN` (not Azure) |
| `mirror-push.yml` | Mirror Push (work repo) | `workflow_dispatch` | **no** | **repo**-level `WORK_GITHUB_PAT` (not Azure) |
| `acr-create.yml` | ACR Create (reusable) | `workflow_call` + `workflow_dispatch` | yes | **org**-level Actions secrets |
| `acr-destroy.yml` | ACR Destroy (reusable) | `workflow_call` + `workflow_dispatch` | yes | **Environment** `AZURE` (caller-resolved on `workflow_call`) |

The filename and the `name:` differ deliberately — the filename encodes what
the workflow *is*, the `name:` is what reads well in the Actions sidebar. When
renaming either, update both this table and README.md; nothing else in the repo
keys off a workflow's display name.

Filenames are `<subject>-<verb>.yml` (`acr-create`, `acr-destroy`) so a
subject's pair sorts together in the directory listing. Keep new workflows to
that shape even when they have no counterpart yet — `mirror-push` follows it
with no `mirror-pull` in sight. The convention is what leaves room for one, not
a requirement to have one.

**Never write a `${{ ... }}` expression inside a `run:` body.** GitHub
substitutes it as raw text before the shell parses the script, so a value
containing a quote or `$(...)` executes on the runner — and in this repo the
affected step was the type-to-confirm guard in front of the `acr-destroy.yml`
destroy, with credentials already in scope. Bind the expression to an `env:` key (safe: the
shell only ever sees a variable) and reference `"$VAR"`. This is Sonar rule
`githubactions:S7630`; every workflow here is currently clean, and a scan of
`run:` bodies for `${{` should stay empty.

**`mirror-push.yml` force-pushes `main` to a private work repository**
(`rubens-gomes_3CC/azure-iac`, a GitHub Enterprise Managed Users namespace).
`main` only — no tags, no `--mirror`, no other branch.

- **It is `workflow_dispatch`-only, deliberately.** `push: branches: [main]` is
  the obvious shape for a mirror and is what every example shows; it is not
  what is wanted. Mirroring publishes into a corporate namespace, and the whole
  point is that *when* stays a decision rather than a side effect of
  committing. Do not "improve" it into an automatic trigger.
- The guards are the `ALLOWED_ACTOR` gate and a check that `github.ref` is
  `refs/heads/main` — the dispatch form's branch selector accepts any branch,
  and whatever it checks out is what gets force-pushed over the mirror's
  `main`. There is no type-to-confirm phrase: unlike the destroys, everything
  in the blast radius is reproducible from here.
- The token is a **repo-level** `WORK_GITHUB_PAT`, and its requirements are
  EMU-specific — see README.md → *Mirroring to the work repository*. It needs
  `Workflows: Read and write` on top of `Contents: Read and write`, because the
  mirrored commits touch `.github/workflows/`; without it the push fails with
  *"refusing to allow a Personal Access Token to create or update workflow"*.
  That is the failure to check first.
- **The work repo receives this directory**, but nothing in it fires there on
  a mirror push: every workflow is either dispatch-only or tag-triggered, and
  no tags are pushed to the mirror. `mirror-push.yml`'s own mirrored copy
  denies at its actor gate. Disable Actions in the work repo anyway — it costs
  nothing, and it means a future automatic trigger cannot surprise you there
  (a dispatch-only `main-verify.yml` would otherwise start failing on every
  mirror push the moment it gained a `push:` trigger, for want of a
  `SONAR_TOKEN` in a different org).
- The push is one-directional and lossy: anything committed directly to the
  mirror's `main` is gone on the next run. Step 4 logs the overwritten SHA
  because the run log is the only record it existed.

**`acr-create.yml` is a reusable workflow** — the CI equivalent of
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
  workflows are not reusable, so they can and do bind it. `acr-destroy.yml`
  *is* reusable and binds it anyway — see below; that is a decision, not an
  oversight.
- Its `plan-*` steps **gate nothing** — `apply-<name>` re-plans internally
  under `-auto-approve` and never reads the `tfplan` that `plan-<name>` wrote.
  They exist for log visibility only.
- `concurrency` is evaluated in the repo that owns the run, so a caller's run
  does not serialise against this repo's own. The azurerm blob lease is the
  real guard — a collision fails with a lock error. Never add `-lock=false`.
  The group string is `acr-lifecycle-<env>`, shared verbatim with
  `acr-destroy.yml` so a create and a destroy of module 06 cannot overlap.
  Lifecycle-shaped, not verb-shaped, for that reason. Changing it in one file
  without the other silently removes the interlock.

**`acr-destroy.yml` is the teardown counterpart.** It takes the same two
triggers as `acr-create.yml` (`workflow_call` + `workflow_dispatch`) but is
asymmetric with it everywhere that matters: gated on `ALLOWED_ACTOR` plus a
typed `DESTROY ACR <name>` phrase, and bound to the `AZURE` Environment so a
required-reviewer gate can be added in repo settings without editing the file.
None of those guards is relaxed on the `workflow_call` path — that is the whole
basis on which a destroy is safe to expose as reusable:

- **`environment: AZURE` is kept on both triggers, deliberately.** For a
  reusable workflow the binding resolves in the *caller's* repo, so a calling
  repository must define an `AZURE` Environment itself before it can invoke
  this. That imposition is the guard — it is why `acr-create.yml` avoids an
  Environment and this one keeps it. Do not make it conditional on
  `github.event_name` to spare callers the setup; that hands every `uses:` an
  ungated destroy.
- Because the Environment can supply the credentials caller-side, the four
  `workflow_call` `secrets:` are declared `required: false`. A caller either
  passes them or lets its `AZURE` Environment provide them; the fail-fast step
  catches the case where neither happened and says so.
- **`acr_name` and `confirm` have no defaults on the `workflow_call` path**,
  though the dispatch form prefills both. A caller has to spell the registry
  name out in its own YAML, so a `uses:` line cannot be a one-word registry
  deletion. Keep them undefaulted.
- **`ALLOWED_ACTOR` applies to callers too.** On `workflow_call`,
  `github.actor` is whoever triggered the *caller's* run, so a push by another
  user or a bot/scheduled upstream trigger is denied at step 2, before any
  credential is touched.
- It destroys **module 06 only** — the registry plus its `AcrPull` role
  assignment. Modules 01 and 04 are never planned. That is structural (module
  06 has its own state key and a destroy can only remove what is in the state
  it is pointed at), but a guard step parses `terraform show -json tfplan` and
  fails the run if the plan proposes deleting anything other than
  `azurerm_container_registry` / `azurerm_role_assignment`.
- The expected registry name is read from
  `terraform/envs/<env>/06-acr/terraform.tfvars`, not hardcoded in the
  workflow — comparing the typed confirmation against anything else would let
  the guard pass while a different registry was torn down.
- Its `concurrency.group` is `acr-lifecycle-<env>` — the *same string* as
  `acr-create.yml`, on purpose. A group only serialises runs that name it
  identically, and the run that must never overlap a destroy is a create of
  the same modules. (It was `provision-acr-<env>` before the workflow files
  were renamed; both files changed together.)
- Deleting the registry deletes every repository, tag, and manifest with it.
  Basic SKU has no soft-delete, so there is no purge step and the name is
  released immediately. The pre-destroy inventory step logs what was in the
  registry because the run log is the only surviving record.
- It uses `make plan-destroy-acr` / `make destroy-acr`. `plan-destroy-<name>`
  is generated by the same Makefile factory as the other per-module targets.

**The state backend has no CI at all, deliberately.** Creating and destroying it
are hand-operated procedures — `terraform/bootstrap-backend/TF_PROVISION.md` for
the two-pass bootstrap, `TF_DESTROY.md` for the teardown. Do not add either
workflow; the reasons are structural, not bugs to fix.

*Why the destroy could not work.* It ran `terraform init` against the **azurerm**
backend and then `terraform destroy -auto-approve` — deleting the Storage
Account that held the state it was writing to. That is exactly the sequence
`backend.tf`'s "Teardown safety" header, the module README and `TF_DESTROY.md`
all forbid; the correct order is comment out the backend block → `terraform init
-migrate-state` → destroy from local state, and the workflow had no step that
could do it. Its last step uploaded `errored.tfstate` — a file Terraform writes
only when it *fails* to persist state — which is the clearest evidence the
design was known-broken (and even that step pointed at the workspace root while
Terraform ran in `terraform/bootstrap-backend`). A partial failure would have
left orphans with no state and no way to re-run, since the next `init` needs the
account just deleted.

*Why the create was near-useless.* Same `init`-first structure, so it could not
bootstrap a backend that did not exist yet — its own step 5 comment said so
("the azurerm backend cannot init against a Storage Account that has not been
created"). That left it able only to re-apply drift on a live four-resource
module, for a solo repo whose owner has local `ARM_*`. The bootstrap is also
inherently two-pass and interactive: pass 2 is `terraform init -migrate-state`,
which prompts, and CI can only get past that with `-force-copy` — turning the
one irreversible state-migration decision into an unattended flag.

*Why a state-importing composite action is not the answer either.* Such an
action assumes Terraform is using the local backend, which is false —
`backend.tf` hardcodes an azurerm backend — so its imports no-op via their
`terraform state show` guards. Guarded imports that swallow failure mean that if
a guard ever stopped holding, a failed import would fall through to planning a
*create* of a resource that already exists.

**Static analysis.** `sonar-project.properties` at the repo root is the single
source of scanner config; `release.yml` step 7 and `make sonar` both read it and
pass no arguments, so CI and local cannot drift. Things that will bite:

- **Automatic Analysis must stay disabled** in the SonarCloud project. It is
  mutually exclusive with CI analysis — with both enabled every CI scan fails
  with *"You are running CI analysis while Automatic Analysis is enabled"*.
  Nothing in the repo can assert this; it is a UI setting.
- `sonar.exclusions` covers `**/.terraform/**` on purpose. `make validate` runs
  first and leaves a `.terraform/modules/` copy of every local module's `.tf`
  files, which `sonar.sources=.` would otherwise index alongside the originals
  — doubling ncloc and raising every finding twice.
- **Every accepted finding is suppressed in `sonar-project.properties`, not in
  the SonarCloud UI or quality profile** — so each exemption is greppable, shows
  up in a diff, and carries its rationale in a comment next to it. Five
  `sonar.issue.ignore.multicriteria` entries today:
  - `e1` — `githubactions:S7637` (pin actions to a full commit SHA) across
    `.github/workflows/*.yml`, against this repo's deliberate major-tag
    convention. Without it the scan action's own `@v8` pin fails the gate it
    adds.
  - `e2`–`e4` — `terraform:S6378` (missing `identity` block) on
    `bootstrap-backend/main.tf`, `modules/acr/main.tf`, `modules/storage/main.tf`.
    These resources are the *targets* of the shared UAMI's auth, not callers.
  - `e5` — `terraform:S6382` (client certificate mode) on
    `modules/container-apps/main.tf`. mTLS on public ingress is not in scope.

  `e2`–`e5` are pinned to **exact file paths, not globs**, on purpose: a new
  module that omits an identity block must still raise the finding. If you add
  a module and see S6378, judge it — do not widen the pattern reflexively.
- `.scannerwork/` is gitignored. Without that, `make sonar` dirties the tree and
  the next `make release-<level>` aborts in `release-check` for a reason that
  looks unrelated.

All four Terraform-touching workflows pin `terraform_version: "1.15.8"` and
`terraform_wrapper: false` (the wrapper intercepts stdout and would break
`terraform output -raw`). Bump the pin in all four together: `main-verify.yml`,
`release.yml`, `acr-create.yml`, `acr-destroy.yml`. `mirror-push.yml` is the
fifth workflow and runs no Terraform, so it carries no pin and is not part of
that bump.

## Repo layout (high level)

- `.github/workflows/` — five workflows; see the CI section above. There are
  no longer any `.github/actions/` composite actions.
- `terraform/bootstrap-backend/TF_PROVISION.md` — hand-operated two-pass
  bootstrap of the state backend; `TF_DESTROY.md` alongside it is the teardown.
  There is deliberately no CI for either; see the CI section.
- `PROVISION_ACR.md` — standalone runbook for provisioning/destroying just the
  ACR (modules 01 → 04 → 06), by hand or via `acr-create.yml` /
  `acr-destroy.yml`.
- `terraform/bootstrap-backend/` — the state backend module (`rg-tfstate`,
  `sttfstaterubens01`, `tfstate` container), plus `INITIAL_SETUP.md` for the
  one-time SP setup. `TF_PROVISION.md` covers the two-pass bootstrap,
  `TF_DESTROY.md` the teardown. Do not touch unless re-bootstrapping.
- `terraform/modules/<name>/` — reusable child modules. No state, no backend.
- `terraform/envs/dev/env.tfvars` — shared env vars (env, location, prefix,
  apps list, tags, PG Entra admin group ID).
- `terraform/envs/dev/backend.hcl` — shared azurerm backend config.
- `terraform/envs/dev/<NN-module>/` — per-module Terraform root. Own state
  key `<module>/terraform.tfstate` inside the tfstate container. Numeric
  prefix encodes dependency order.
- `docs/PROVISIONING_PLAN.md` — the master plan.
- `terraform/bootstrap-backend/INITIAL_SETUP.md` — one-time SP creation, provider registration,
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

- **Check a region before moving the estate to it**. The subscription is
  offer-restricted from provisioning PG Flexible Server in some regions, which
  is what forced module 09's old per-module override. Verify with
  `az postgres flexible-server list-skus --location <region>` before editing
  `location` in `env.tfvars`.
- **The state backend's region is independent of the estate's**, and changing it
  is destructive. `backend.hcl` has no region field, and the azurerm backend
  addresses state by RG + account + container name, so a state blob's region
  does not matter. But `location` is ForceNew on `azurerm_resource_group`:
  editing it in `bootstrap-backend/terraform.tfvars` plans a destroy of
  `rg-tfstate` and every state blob under it, and Azure cannot move a Storage
  Account between regions, so it would also need a new globally-unique name.
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
- **"Not authorized or project not found ... check the `SONAR_TOKEN`" from the
  release workflow is usually NOT a token problem.** `release.yml` fires on a
  tag push, so `GITHUB_REF` is `refs/tags/vX.Y.Z`; the scanner auto-detects
  GitHub Actions and submits the analysis as a SHORT-lived branch of that name.
  The submit succeeds, then the gate lookup
  (`api/qualitygates/project_status?analysisId=...`) 403s, because short-lived
  branch gate status is not readable on this plan — and the scanner reports
  that as a credentials error. `release.yml` passes
  `args: -Dsonar.branch.name=main` to prevent it. Diagnose this class of
  failure by reading the DEBUG log for the `api/ce/submit` URL and checking
  whether `characteristic=branch=` says anything other than `main`, and by
  hitting `api/qualitygates/project_status?analysisId=<id>` anonymously — if it
  403s without a token, no token change will fix it.
- **`sonar.branch.name=main` IS pinned in `sonar-project.properties`**, and all
  three callers (`main-verify.yml`, `release.yml`, `make sonar`) pass the
  scanner no arguments at all. `main` is the only branch, so there is one
  correct value. The pin is load-bearing for `release.yml`: it fires on a tag
  ref, which without it is submitted as a short-lived branch whose gate lookup
  403s on this plan — that is what cost the v0.3.0 release. It was briefly
  removed for the PR-only model (v0.4.0–v0.4.2), when a global pin would have
  made every PR analysis overwrite main's; restore the per-caller arguments
  only if pull requests ever come back.
- **`make sonar` refuses to run off `main`**, because it would publish that
  branch's code as main's analysis.
- **Nothing scans between commits unless you ask.** The tag gate
  (`release.yml`) scans automatically; `main-verify.yml` is dispatch-only. To
  scan before tagging, either run `make sonar` locally or dispatch
  `main-verify.yml` — the dispatch is usually better, since it runs natively on
  Linux. On Apple Silicon the
  scanner image runs emulated and blames through JGit rather than the git CLI —
  measured at minutes for ~144 files against ~1s for native `git blame`, and
  worse once `main` has merge commits for JGit to walk both parents of.
  `SCM blame is in progress..` means it is working, not hung. Let CI do it.
- **`make sonar` stopping dead at "SCM Publisher N source files to be
  analyzed" — with no "blame is in progress" line — is a different thing: a
  git ownership problem, not a slow scan.** The scanner container runs as uid
  1000 while the bind-mounted tree belongs to the host user, so git rejects the
  repo with *detected dubious ownership* and the SCM publisher falls back off
  the native blame path onto its own history walk — which, on an amd64 image
  emulated on Apple Silicon over a macOS bind mount, looks exactly like a hang.
  The `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` trio in the
  `sonar` recipe sets `safe.directory` through the environment and fixes it.
  Do not reach for `sonar.scm.disabled=true` instead: every quality-gate
  condition is a `new_*` metric, and those are attributed from blame data, so
  disabling SCM changes which findings the gate counts. CI is unaffected —
  it runs natively on Linux against its own checkout.
- **`make sonar` dirties the tree, and `release-check` fails on a dirty tree.**
  The scanner writes `.scannerwork/` at the repo root. It is gitignored, so this
  only bites if that entry is ever removed — the symptom is a `make release-*`
  that aborts complaining about uncommitted changes right after a scan.
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
