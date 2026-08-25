## What and why

<!-- What changes, and what problem it solves. Link an issue if there is one. -->

## Infra impact

<!--
Which modules does `terraform plan` touch, and how? This drives the semver
level of the next release (RELEASING.md):

  MAJOR  plan destroys, recreates or renames an existing resource
  MINOR  additive - new module, new resource, new variable with a safe default
  PATCH  in-place only, or docs / CI / Makefile

Write "none" for a docs-, CI- or Makefile-only change.
-->

none

## Checklist

- [ ] `CHANGELOG.md` `[Unreleased]` updated — a release refuses to cut on an
      empty `[Unreleased]`, and the entry is easiest to write now
- [ ] Ran `make validate` locally, or the `terraform` check is green
- [ ] Docs updated if this changes a documented behaviour — `README.md`,
      `CLAUDE.md`, `RELEASING.md`, `docs/PROVISIONING_PLAN.md`
- [ ] No GitHub `${{ ... }}` expression added inside a workflow `run:` body —
      bind it through `env:` first (the `workflows` check enforces this)

<!--
Merging: squash only. main is PR-only; the `terraform` and `workflows` checks
must pass. Releases go through their own release/vX.Y.Z PR - see RELEASING.md.
-->
