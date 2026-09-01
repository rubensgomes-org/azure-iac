# Static analysis — SonarCloud

`sonar-project.properties` at the repo root is the single source of scanner
config; `release.yml` step 7 and `make sonar` both read it and
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
