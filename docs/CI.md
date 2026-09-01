# CI — GitHub Actions

Reference for the five workflows in `.github/workflows/`. Read this before
editing any workflow file. SonarCloud configuration is in `SONAR.md`.

## Overview

Five workflows, three credential models. All Azure-touching workflows get
`ARM_*` from GitHub secrets holding the same `terraform-sp` Service Principal
documented under *Auth model* in `CLAUDE.md`. The other two models are `SONAR_TOKEN`, which
reaches sonarcloud.io and nothing else, and `WORK_GITHUB_PAT`, which reaches
one private repository in a work GitHub namespace and nothing else. Neither can
touch the subscription; keep it that way.

**`TF_VAR_rg_suffix` is a repository-level Actions *variable*, and the only
one.** Everything else the CI reads is a secret; this is the repo's first and
so far only use of the `vars` context. It is bound at job level in
`acr-create.yml` and nowhere else, and that one binding feeds two consumers:
Terraform reads `TF_VAR_rg_suffix` for module 01's `rg_suffix` input, and Make
imports the same environment variable to build `RG_SUFFIX` (`Makefile:56`) for
the orphan sweep. There is deliberately **no workflow input** — no per-run
knob, and no caller passes it. `acr-destroy.yml` does not bind it: with module
06 alone in scope it touches no resource group and runs no sweep.

- **Unset means the historical `rg-<env>-<purpose>` names**, byte for byte. The
  empty string is simultaneously module 01's declared default and Make's falsy
  value, so no code path needs a conditional for it.
- **Write the `env:` key in exactly that case.** GitHub variable names are
  case-insensitive on lookup, so `vars.TF_VAR_rg_suffix` resolves however the
  variable happens to be stored — but Terraform's are not. `TF_VAR_RG_SUFFIX`
  maps to an undeclared variable `RG_SUFFIX`, which Terraform ignores *without
  warning*, and the run quietly produces unsuffixed names.
- **Changing it on a live estate is a destroy+recreate of all five RGs**, not a
  rename — `name` is ForceNew on `azurerm_resource_group`, and every resource
  inside those RGs is owned by a different state file that knows nothing about
  it. `acr-create.yml` refuses rather than plan it, comparing the implied name
  against module 01's state before planning. Set it at first provision or after
  a full teardown, never in between.
- **It does not change what a destroy removes** — a destroy works from state.
  What it decides is which RG `make purge-orphans` sweeps, which matters for
  the repo-root `make destroy` and no longer for any workflow. A wrong value
  makes that a silent no-op (`|| true`), leaves the Smart Detection action
  group standing, and module 01's RG delete then fails on
  `prevent_deletion_if_contains_resources` with an error naming none of this.
- **`vars` resolves in the caller's repository on the `workflow_call` path**,
  the same caller-resolution shape as `environment:`. Nothing calls
  `acr-create.yml` today, so this is a documented caveat rather than a live
  problem; a future caller has to define its own variable of the same name.
- Setting a suffix does **not** by itself give you a second parallel estate.
  `acr_name` in `06-acr/terraform.tfvars` is a fixed global literal and will
  collide, and every module keeps one state key regardless of suffix — so two
  suffixes are two configurations of the *same* state.

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
an application repo can gate its image push on it with `needs:`. **No
repository calls it today** — it is a published interface waiting for a
consumer, not a live dependency of one. `rubensgomes-org/spring-blueprint` was
long documented here as the first consumer; it is not, and calls
`rubensgomes-org/azure-workflows` instead. Verify before relying on that claim
again — the `workflow_call` design decisions below rest on it.

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
- **Module 01 is split across three steps** — `init-resource-groups`, then the
  `rg_suffix` drift guard, then `plan`/`apply`. The split exists so the guard
  can read module 01's current state via `terraform output -raw
  rg_platform_name` before anything is planned against it. The extra `init` is
  cached and idempotent. Do not recombine them.
- `concurrency` is evaluated in the repo that owns the run, so a caller's run
  does not serialise against this repo's own. The azurerm blob lease is the
  real guard — a collision fails with a lock error. Never add `-lock=false`.
  The group string is `acr-lifecycle-<env>`, shared verbatim with
  `acr-destroy.yml` so a create and a destroy of the registry cannot overlap.
  Lifecycle-shaped, not verb-shaped, for that reason. Changing it in one file
  without the other silently removes the interlock.

**`acr-destroy.yml` destroys the container registry — module 06 and nothing
else.** It is deliberately *not* the inverse of `acr-create.yml`, which applies
01, 04 and 06: the shared UAMI and the five RGs are left standing. It briefly
destroyed all three; the scope was narrowed back, and the pre-flight estate
guard and the `STACK` confirmation phrase went with it. It takes the same two
triggers as `acr-create.yml` (`workflow_call` + `workflow_dispatch`) but is
asymmetric with it in ceremony: gated on `ALLOWED_ACTOR` plus a typed
`DESTROY ACR <name>` phrase, and bound to the `AZURE` Environment so a
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
- **There is no pre-flight estate check, and that is a decision.** One used to
  abort the run if the five RGs held anything outside the ACR stack. It existed
  because the run deleted the RGs and the shared UAMI, which against a live
  estate would remove the identity every microservice authenticates with and
  then fail at the RG delete, leaving the estate half-destroyed. With module 06
  alone in scope there is no such outcome: dropping the registry is survivable
  and reversible with `make apply-acr`. Do not reintroduce the guard without
  also rewidening the scope — as an abort it would refuse every run against a
  deployed estate, which is the case this workflow now exists for.
- **The plan-scope guard is now the only scope guard.** A script written to
  `$RUNNER_TEMP` parses `terraform show -json tfplan` and fails the run if the
  plan deletes anything other than `azurerm_container_registry` or
  `azurerm_role_assignment`. Belt-and-braces — module 06 has its own state key
  and a destroy can only remove what is in the state it is pointed at — but it
  is what turns "we believe the scope is right" into a run that refuses to
  proceed if it isn't. It takes the module directory and the allowlist as
  arguments, so a second call site can be added without copying it.
- **`TF_VAR_rg_suffix` is not bound here.** It mattered only for
  `make purge-orphans`, which ran between modules 04 and 01; module 06 neither
  declares that variable nor touches a resource group. `acr-create.yml` still
  binds it. The sweep step is gone with module 01.
- **The final step asserts what survived, not just what went.** `rg-tfstate`
  must still exist — a scoping mistake reaching the backend would destroy every
  module's state with no way to `terraform init` again — and so must
  `id-<env>-app` and the `rg-<env>-*` groups. Their absence is reported as a
  WARNING rather than a failure, since they may legitimately never have been
  applied, but it is the signal that the destroy scope leaked.
- The expected registry name is read from
  `terraform/envs/<env>/06-acr/terraform.tfvars`, not hardcoded in the
  workflow — comparing the typed confirmation against anything else would let
  the guard pass while a different registry was torn down.
- **The confirmation phrase is `DESTROY ACR <name>`.** It was
  `DESTROY ACR STACK <name>` while the workflow destroyed 06, 04 and 01, and
  the word went when that scope did: the phrase has to describe what the run
  deletes, since informed consent is the entire point of a type-to-confirm
  gate. Both renames are breaking changes for a caller, on purpose. The
  safeguard step prints a note when it sees the old phrase.
- Its `concurrency.group` is `acr-lifecycle-<env>` — the *same string* as
  `acr-create.yml`, on purpose. A group only serialises runs that name it
  identically, and the run that must never overlap a destroy is a create of the
  same registry. Changing it in one file without the other silently removes the
  interlock.
- Deleting the registry deletes every repository, tag, and manifest with it.
  Basic SKU has no soft-delete, so there is no purge step and the name is
  released immediately. The pre-destroy inventory step logs what was in the
  registry because the run log is the only surviving record.
- It uses `make plan-destroy-acr` and `make destroy-acr`, generated by the same
  Makefile factory as the other per-module targets; the workflow reimplements
  nothing.

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

## Terraform version pin

All four Terraform-touching workflows pin `terraform_version: "1.15.8"` and
`terraform_wrapper: false` (the wrapper intercepts stdout and would break
`terraform output -raw`). Bump the pin in all four together: `main-verify.yml`,
`release.yml`, `acr-create.yml`, `acr-destroy.yml`. `mirror-push.yml` is the
fifth workflow and runs no Terraform, so it carries no pin and is not part of
that bump.
