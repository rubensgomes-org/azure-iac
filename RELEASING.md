# Releasing

How a release is cut in this repo, and what the version number means.

Releases are **manual and explicit**. You decide the bump level; nothing infers
it from commit messages. There is no branch/PR flow — work lands on
`main`, and a release is a tagged commit on `main`.

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
# 1. Land your work on main and record it under [Unreleased] in CHANGELOG.md.
#    A release refuses to proceed if [Unreleased] has no entries.

# 2. Check the SonarCloud quality gate BEFORE tagging. release.yml runs the
#    same scan and refuses to publish if the gate is red -- but by then the tag
#    is already pushed and cannot be moved (see "Undoing a release").
export SONAR_TOKEN=<your token>
make sonar

# 3. See where you are and what each bump would produce.
make version
make release-check

# 4. Bump. Writes VERSION, rolls the changelog, commits, creates the
#    annotated tag. All LOCAL — nothing is pushed.
make release-patch      # or release-minor / release-major

# 5. Inspect.
git show --stat HEAD
git tag -l

# 6. Publish. This pushes main and the tag, which fires release.yml.
make release-push
```

`make sonar` runs the identical scan CI runs, reading the same
`sonar-project.properties`, so the two cannot disagree. It publishes its results
to SonarCloud — run it on a clean tree at the commit you are about to tag, not
over work in progress.

`make release-tag` is the one-off variant: it tags the current `VERSION`
without bumping. It requires `CHANGELOG.md` to already contain a section for
that version, so it only helps when a bump committed cleanly but the tag was
lost or deleted. It is never the way to cut a *new* release — `[Unreleased]`
has no version heading for it to find. Use `make release-<level>` for that.

**Where the repo is now.** `VERSION` is `0.2.0` and `git tag -l` lists
`v0.0.1` … `v0.2.0`. Everything so far has been CI, Makefile, and
documentation work: no release to date has changed a Terraform resource, so
none has moved the estate. Run `make version` for the authoritative current
value rather than trusting this paragraph.

### Preflight checks

`make release-check` (also run automatically by every release target) fails on:

- a missing or malformed `VERSION` (must be `N.N.N`);
- a dirty working tree — staged or unstaged;
- being on a branch other than `main`;
- `HEAD` being behind `origin/main` (fetch failures are a warning, not an error,
  so the targets still work offline);
- an empty `[Unreleased]` section (bump targets only);
- a tag for the target version already existing.

## Undoing a release

Trivial before `make release-push`, because nothing has left your machine:

```bash
git tag -d v$(cat VERSION)
git reset --hard HEAD~1
```

That order matters: `git reset` first and you have a tag pointing at a commit
that no longer exists on any branch.

After the push, do **not** delete or move the tag — cut a new patch release
instead. A published tag that later points at different code is worse than a
release you regret.

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
   every resource in all twelve modules. That diff is the intended signal:
   the code is at 0.2.0, Azure is still labelled 0.1.0. It clears on the next
   `make apply`.
2. **The stamp records the release, not the commit.** Applying uncommitted
   work-in-progress labels the resources with the last release number. If you
   want the estate to say `0.2.0`, cut `0.2.0` first, then apply.

Tag changes are in-place updates in `azurerm` — no resource is replaced by a
version bump. Confirm with `make plan-resource-groups` if you want to see it.

## What CI does on a tag

`.github/workflows/release.yml` runs on any pushed tag matching `v*.*.*`:

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

**If the gate fails, the tag is already pushed.** Step 5 runs after the tag
exists, so a red gate leaves a tag with no GitHub Release behind it. Do not
delete or move the tag — fix the findings and cut the next patch release, per
"Undoing a release" above. `make sonar` before step 4 of the recipe is how you
avoid being in that position.
