# Releasing

How a release is cut in this repo, and what the version number means.

Releases are **manual and explicit**. You decide the bump level; nothing infers
it from commit messages.

`main` is **PR-only**: every commit, releases included, reaches it through a
pull request whose checks pass. A release is therefore two steps rather than
one — a *release PR* that bumps `VERSION` and rolls the changelog, and then a
tag placed on `main` **after** that PR merges. Tagging after the merge is not
ceremony: a squash-merge rewrites the commit SHA, so a tag created locally
before merging would point at a commit that never reaches `main`.

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
# 1. Get main current. Every feature PR that belongs in this release is merged,
#    and each one recorded its own entry under [Unreleased] in CHANGELOG.md.
#    A release refuses to proceed if [Unreleased] has no entries.
git switch main && git pull

# 2. See where you are and what each bump would produce.
make version
make release-check

# 3. Bump on a release branch. Writes VERSION, rolls the changelog, commits.
#    Does NOT tag -- the tag comes after the merge.
git switch -c release/v0.4.1
make release-prep-patch       # or release-prep-minor / release-prep-major

# 4. Open the release PR. pr-verify.yml runs terraform + workflows + sonar;
#    all three must pass before GitHub will let it merge.
git push -u origin release/v0.4.1
gh pr create --title "release: v0.4.1" --fill

# 5. Merge it (squash), then tag main's real tip.
git switch main && git pull
make release-tag

# 6. Publish. Pushes the tag, which fires release.yml.
make release-push
```

That is the whole procedure. There is **no local Sonar step** — the release PR
in step 4 is gated on the `sonar` check, so a red quality gate blocks the merge
before a tag exists at all, and `release.yml` scans once more at tag time. You
get the gate twice without running it yourself.

`make sonar` still exists as a local fallback, but it is **not part of this
recipe**, and on Apple Silicon it is close to unusable: the scanner image is
amd64-only, so it runs under emulation, and its JGit blame pass over a
bind-mounted tree takes minutes where native `git blame` over the same files
takes about one second. Reach for it only to reproduce a CI Sonar failure
locally, and expect to wait. It analyses `main` and refuses to run anywhere
else — on a feature branch it would overwrite main's analysis with unmerged
code.

`make release-patch|minor|major` no longer exist. They bumped, committed *and*
tagged in one shot on `main`, which cannot work when `main` is PR-only. They now
fail with a pointer to this recipe rather than leaving you holding an unpushable
tag.

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
- being on the wrong branch for the step: `release-prep-*` requires a
  `release/*` branch, everything else requires `main`;
- `HEAD` being behind `origin/main` (fetch failures are a warning, not an error,
  so the targets still work offline);
- an empty `[Unreleased]` section (bump targets only);
- a tag for the target version already existing.

## Undoing a release

How much you can undo depends on which of the two phases you are in.

**Before the release PR is merged** — nothing has affected `main`. Close the PR
and delete the branch, or just fix it and push again:

```bash
git switch main
git branch -D release/v0.3.2
git push origin --delete release/v0.3.2
```

**After the merge but before `make release-push`** — the release commit is on
`main` and is not yours to reset; only the tag is local:

```bash
git tag -d v$(cat VERSION)
```

If you decide not to release that version at all, the `VERSION` bump and the
dated `CHANGELOG.md` heading are already on `main`, so the honest fix is to go
forward: tag it, or open another PR that rolls the section back to
`[Unreleased]`.

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
   `make release-prep-minor`, `terraform plan` shows a pending `~ tags` update on
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

(`pr-verify.yml` already ran the same `fmt`, `validate` and Sonar checks on the
release PR, so by the time a tag exists this should be a formality. It is
repeated here because a tag can be pushed for a commit whose PR checks passed
weeks earlier — and because this is the last gate before something is published
under your name.)

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

That should now be rare: the release PR was gated on the same Sonar check, so
for the gate to be red here, something has to have changed between the merge and
the tag. It is not impossible — the gate is evaluated against SonarCloud's
current state, and a quality-profile change or a new-code-period roll can turn
it red with no commit involved.
