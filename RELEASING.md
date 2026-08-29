# Releasing

How a release is cut in this repo, and what the version number means.

Releases are **manual and explicit**. You decide the bump level; nothing infers
it from commit messages.

This repo is **trunk-based**: `main` is the only branch, every change is
committed straight to it, and there are no feature branches and no pull
requests. A release is therefore one command — bump `VERSION`, roll the
changelog, commit and tag, all locally — followed by one deliberate push.
Nothing rewrites the release commit between the tag and the push, which is what
makes the single-command form safe here.

## The moving parts

| Thing                           | Role                                                                                          |
|---------------------------------|-----------------------------------------------------------------------------------------------|
| `VERSION`                       | Single source of truth. One line, bare `MAJOR.MINOR.PATCH`, no `v`.                           |
| Git tag                         | `v<VERSION>` — annotated, created on the release commit.                                      |
| `CHANGELOG.md`                  | Keep a Changelog. `[Unreleased]` accumulates; the release renames it.                         |
| `release` resource tag          | Every Azure resource carries `release = <VERSION>`, read from `VERSION` by Terraform.         |
| `.github/workflows/release.yml` | Fires on the tag push: gates on consistency + `fmt` + `validate`, publishes a GitHub Release. |

## What MAJOR / MINOR / PATCH mean here

"Breaking change" means something different for infrastructure than it does for
a library. The question is not *does the API change* but *what does
`terraform plan` do to resources that already exist*.

### MAJOR — existing infrastructure is destroyed or renamed

Bump MAJOR when the change would, on an already-applied estate:

- destroy and recreate a stateful resource — Key Vault, Storage, PostgreSQL
  Flexible Server, Service Bus, ACR (`plan` shows `-/+ destroy and then create`
  or `# forces replacement`);
- change a resource **name**, since in Azure the name *is* the identity;
- remove a module, or change the resource-group partitioning (§3 of the plan);
- break an output that another module consumes through remote state;
- require a manual step during upgrade (an import, a state move, a data
  migration).

A MAJOR release is a warning that you cannot roll forward with a plain
`make apply` and walk away.

### MINOR — new capability, additive plan

- A new module, or new resources inside an existing one.
- A new variable with a safe default, or a new entry in `apps`.
- New Makefile targets, new workflows.
- A provider or Terraform CLI **minor** bump (`~> 4.80` → `~> 4.81`).

`terraform plan` is additive or in-place; nothing existing is lost.

### PATCH — no resource churn

- Tag, SKU, retention, or other in-place attribute tweaks.
- Documentation, comments, `terraform fmt`.
- CI and Makefile fixes.
- Bug fixes where `plan` shows only `~ update in-place`.

**When in doubt, run `make plan-<module>` and let the plan decide.** Any
`destroy`/`replace` line on a resource that holds data is a MAJOR.

### Pre-1.0

The project is at `0.x` while the deferred work in
`docs/PROVISIONING_PLAN.md` is outstanding — most importantly D1 (real Spring
Boot images in module 11) and D2 (Application Insights wiring). Under `0.x`,
MINOR absorbs breaking changes; the rules above apply as written from `1.0.0`
onward.

**`1.0.0` is cut when a full `make apply` from zero brings up all twelve modules
with real application images and verifies clean.**

## Cutting a release

```bash
# 1. Get main current. Every change in this release is already committed, and
#    each one recorded its own entry under [Unreleased] in CHANGELOG.md.
#    A release refuses to proceed if [Unreleased] has no entries.
git switch main && git pull

# 2. See where you are and what each bump would produce.
make version
make release-check

# 3. Bump. Writes VERSION, rolls the changelog, commits AND tags -- all local.
make release-patch            # or release-minor / release-major

# 4. Publish. Pushes main, then the tag, which fires release.yml.
make release-push
```

That is the whole procedure. Steps 3 and 4 are split so a mistyped level or a
bad changelog roll never escapes the machine: until `release-push`, both the
commit and the tag are local and a `git tag -d` + `git reset --hard HEAD~1`
undoes them completely.

There is **no local Sonar step**. `main-verify.yml` has already scanned every
commit going into the release, and `release.yml` scans once more at tag time,
so you get the gate twice without running it yourself.

`make sonar` exists as a local fallback, but it is **not part of this recipe**,
and on Apple Silicon it is close to unusable: the scanner image is amd64-only,
so it runs under emulation, and its JGit blame pass over a bind-mounted tree
takes minutes where native `git blame` over the same files takes about one
second. Reach for it only to reproduce a CI Sonar failure locally, and expect
to wait. It analyses `main` and refuses to run anywhere else.

`make release-tag` is an escape hatch, not part of the recipe: it tags the
current `VERSION` without bumping. It requires `CHANGELOG.md` to already
contain a section for that version, so it only helps when a bump committed
cleanly but the tag was lost or deleted before it was pushed. It can never cut
a *new* release — `[Unreleased]` has no version heading for it to find.

**Where the repo is now.** Run `make version` for the authoritative current
value. Everything released so far has been CI, Makefile, and documentation
work: no release to date has changed a Terraform resource, so none has moved
the estate.

### Preflight checks

`make release-check` (also run automatically by every release target) fails on:

- a missing or malformed `VERSION` (must be `N.N.N`);
- a dirty working tree — staged or unstaged;
- not being on `main` — every release target requires it;
- `HEAD` being behind `origin/main` (fetch failures are a warning, not an error,
  so the targets still work offline);
- an empty `[Unreleased]` section (bump targets only);
- a tag for the target version already existing.

## Undoing a release

`make release-push` is the dividing line. Everything before it is local.

**Before `make release-push`** — the release commit and the tag are both on
this machine only, and nothing has reached `origin`:

```bash
git tag -d v$(cat VERSION)
git reset --hard HEAD~1
```

That restores `VERSION` and `CHANGELOG.md` exactly as they were. Check with
`git status` and `make version` before doing anything else.

**After `make release-push`** — do **not** delete or move the tag. Cut a new
patch release instead. A published tag that later points at different code is
worse than a release you regret. This is also what happens when the quality gate
fails: the tag is pushed, no GitHub Release is created, and the fix is the next
patch — see `CHANGELOG.md` `[0.3.1]` for a worked example.

## The `release` tag on Azure resources

Every module root computes:

```hcl
locals {
  release = trimspace(file("${path.root}/../../../../VERSION"))
}
```

and merges `release = local.release` into the shared tag map, so every resource
in the estate records which release provisioned it:

```bash
az group show -n rg-dev-app --query tags
```

Two consequences worth internalising:

1. **A version bump immediately puts the estate "behind".** Right after
   `make release-minor`, `terraform plan` shows a pending `~ tags` update on
   every resource in all twelve modules. That diff is the intended signal —
   the code is at the new release, Azure is still labelled with the previous
   one. It clears on the next `make apply`.
2. **The stamp records the release, not the commit.** Applying uncommitted
   work-in-progress labels the resources with the last release number. If you
   want the estate to carry a given version, cut that release first, then
   apply.

Tag changes are in-place updates in `azurerm` — no resource is replaced by a
version bump. Confirm with `make plan-resource-groups` if you want to see it.

## What CI does on a tag

`.github/workflows/release.yml` runs on any pushed tag matching `v*.*.*`:

(`main-verify.yml` already ran the same `fmt`, `validate` and Sonar checks when
the release commit was pushed, so by the time this fires it should be a
formality. It is repeated here because a tag can be pushed for a commit whose
checks went green weeks earlier — and because this is the last gate before
something is published under your name.)

1. Fails if `v$(cat VERSION)` does not equal the tag name.
2. Fails if `CHANGELOG.md` has no section for that version.
3. `terraform fmt -check -recursive terraform/`.
4. `make validate` — all twelve roots, `-backend=false`.
5. SonarCloud static analysis. **Fails the run if the quality gate is red**, so
   no Release is published over failing analysis.
6. Publishes a GitHub Release whose body is that version's changelog section.

It holds **no Azure credentials** by design. Pushing a release tag can never
touch the estate; applying is always something you do deliberately from your
workstation with `make apply`. The one secret it does carry is `SONAR_TOKEN`,
an organization Actions secret that reaches sonarcloud.io and nothing else.

**If the gate fails here, the tag is already pushed.** Step 5 runs after the tag
exists, so a red gate leaves a tag with no GitHub Release behind it. Do not
delete or move the tag — fix the findings and cut the next patch release, per
"Undoing a release" above.

That should be rare: `main-verify.yml` ran the same Sonar check when the release
commit was pushed, so for the gate to be red here, something has to have changed
between that run and the tag. It is not impossible — the gate is evaluated against SonarCloud's
current state, and a quality-profile change or a new-code-period roll can turn
it red with no commit involved.
