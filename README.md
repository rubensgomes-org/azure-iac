# azure-iac

A playground project to demonstrate the use of IaC (e.g. Terraform) and CICD
pipelines (e.g., GitHub Actions Workflow)  to plan/create/destroy several
infrastructure resources (e.g., resource group, storage account, networking, app
configuration, container registry, container app, blob storage, service bus, and
database) in Azure Cloud.

**Making a change?** Start at
[Working on this project](#working-on-this-project) — `main` is protected, so
the first step is always a feature branch.

## AI-Assisted Development

This project was developed primarily using AI-assisted code generation. All
generated content was reviewed, tested, and refined by human contributors. See
the LICENSE file for additional information regarding AI-generated content.

## Microsoft Links

- [Microsoft Accounts](https://account.microsoft.com/)
- [Microsoft Azure](https://portal.azure.com/)

## Account Info

You will need to have an Azure account. For example:

- account email:       <SECRET_INFO>
- tenant id:           <SECRET_INFO>
- subscription name:   <SECRET_INFO>
- subscription id:     <SECRET_INFO>

## Pre-requisites

The following pre-requisites must be met:

- Microsoft Azure account
- GitHub account
- Ubuntu Linux or MacOS (to run CLI commands)
- Azure CLI 2.88+
- Terraform 1.15.x+

## Application and Infra-structure Requirements

Microservice application requirements:

- Java 25
- Spring Boot 4.1.x+
- Spring Cloud Azure SDK 7.4.x+
- PostgreSQL 18.x+

At a minimum the following Azure infrastructure requirements:

- Azure App Configuration to store some application configurations
- Azure KeyVault to store secret (e.g., password) configurations
- Azure Container Registry (ACR) to store dockerized images
- Azure App Container (ACA) environment to deploy containerized application
- Azure PostgreSQL Server internal private database

The following are planned for later:

- Azure Web Application Firewall (WAF) to block malicious requests
- Microservice REST API end-points publicly reachable (e.g., browsers)

## Infrastructure Configuration

The authentication of Terraform against Azure is based on using a `Service
Principal + Secrets`. Follow the steps
in [INITIAL_SETUP](./terraform/INITIAL_SETUP.md) before running with the Phase 0
below.

### Bootstrap Terraform Backend Module (bootstrap-backend)

This steps is done only once. It creates the following base resources required
by Terraform:

- Terraform Resource group
- Terraform Storage account
- Terraform Blob Container

### Tearing everything down

From the repo root, with the `ARM_*` variables exported **and** a separate
`az login` session active (the az CLI does not inherit `ARM_*`):

```bash
make destroy   # walks modules 12 → 01, sweeping Azure-generated orphans
```

Verify with `az group list -o table` — no `rg-dev-*` rows should remain.
`rg-tfstate` and `NetworkWatcherRG` are expected to survive.

See [§15 of the provisioning plan](./docs/PROVISIONING_PLAN.md) for the full
procedure: verification commands, what legitimately survives, how to remove the
state backend itself, and the failure modes that can make a destroy silently do
nothing.

## GitHub Actions

Six workflows live in [`.github/workflows/`](./.github/workflows/). Four of them
authenticate to Azure with the same `terraform-sp` Service Principal used
locally; `release.yml` and `pr-verify.yml` deliberately hold no Azure
credentials (their only secret is `SONAR_TOKEN`, which reaches sonarcloud.io and
nothing else).

| Workflow                                                                   | Shows in Actions as        | Trigger                              | What it does                                                                                                                                                                                  |
|----------------------------------------------------------------------------|----------------------------|--------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`acr-create.yml`](./.github/workflows/acr-create.yml)                     | **ACR Create (reusable)**  | `workflow_call`, `workflow_dispatch` | Applies modules 01 → 04 → 06 so a registry exists and is writable. Publishes `acr_name` / `acr_login_server` outputs.                                                                         |
| [`acr-destroy.yml`](./.github/workflows/acr-destroy.yml)                   | **ACR Destroy (reusable)** | `workflow_call`, `workflow_dispatch` | Destroys module 06 only — the registry and every image in it. Resource groups (01) and the shared UAMI (04) are left standing. Actor-restricted and type-to-confirm guarded on both triggers. |
| [`tf-bootstrap-create.yml`](./.github/workflows/tf-bootstrap-create.yml)   | **TF Bootstrap Create**    | `workflow_dispatch`                  | Creates/updates the state backend (`rg-tfstate`, `sttfstaterubens01`, `tfstate`).                                                                                                             |
| [`tf-bootstrap-destroy.yml`](./.github/workflows/tf-bootstrap-destroy.yml) | **TF Bootstrap Destroy**   | `workflow_dispatch`                  | Tears the state backend down.                                                                                                                                                                 |
| [`pr-verify.yml`](./.github/workflows/pr-verify.yml)                       | **PR Verify**              | `pull_request` → main                | Three required checks on every PR: `terraform`, `workflows`, `sonar`. See Branching.                                                                                                          |
| [`release.yml`](./.github/workflows/release.yml)                           | **Release (tag push)**     | tag `v*.*.*`                         | Validates the tag against `VERSION` + `CHANGELOG.md`, runs `fmt`/`validate` and the SonarCloud quality gate, publishes a GitHub Release.                                                      |

The middle column is the `name:` each workflow declares — that is the label in
the repository's **Actions** sidebar, which is where you start the manual ones.

`acr-destroy.yml` is the inverse of `acr-create.yml` and is reachable the same
two ways, but it is not its mirror image. Three guards apply on **both**
triggers, callers included: the run is restricted to a single GitHub actor, it
refuses to proceed until the phrase `DESTROY ACR rubensdevacr` is supplied
exactly, and it asserts the blast radius from the destroy plan before touching
anything — a plan proposing to delete a resource group or a managed identity
aborts the run. It destroys **only** module 06. Every image and repository in
the registry is deleted permanently; the registry *name* is fixed in
`terraform.tfvars`, so re-running `acr-create.yml` brings it back at the same
login server and only the images need repushing.

Note the asymmetry in Environment binding. `acr-create.yml` binds no GitHub
Environment, because for a reusable workflow `environment:` resolves in the
*caller's* repository and imposing that setup on callers of a create is
pointless friction. `acr-destroy.yml` keeps `environment: AZURE` for exactly
that reason inverted — a repository cannot call the destroy until someone has
deliberately created an `AZURE` Environment there, and can attach required
reviewers to it.

### Provisioning the ACR from an application pipeline

`acr-create.yml` is a **reusable** workflow. An application repository calls it
and gates its image push on the result, so the registry hostname is never
hardcoded on the application side:

```yaml
jobs:
  provision-acr:
    uses: rubensgomes-org/azure-iac/.github/workflows/acr-create.yml@main
    with:
      environment_name: dev          # optional; defaults to dev
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
      AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

  push-image:
    needs: provision-acr
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: azure/login@v3
        with:
          auth-type: SERVICE_PRINCIPAL
          creds: >-
            {"clientId":"${{ secrets.AZURE_CLIENT_ID }}",
             "clientSecret":"${{ secrets.AZURE_CLIENT_SECRET }}",
             "tenantId":"${{ secrets.AZURE_TENANT_ID }}",
             "subscriptionId":"${{ secrets.AZURE_SUBSCRIPTION_ID }}"}
      - run: |
          az acr login --name "${{ needs.provision-acr.outputs.acr_name }}"
          docker build -t "${{ needs.provision-acr.outputs.acr_login_server }}/api:${{ github.sha }}" .
          docker push  "${{ needs.provision-acr.outputs.acr_login_server }}/api:${{ github.sha }}"
```

The four secrets are organization-level Actions secrets on `rubensgomes-org`
and must be **shared with the calling repository**. Pass them explicitly rather
than using `secrets: inherit` — this SP has subscription-wide write access, and
the explicit list is the only record of which credentials cross a repo boundary.

### Destroying the ACR from another pipeline

`acr-destroy.yml` is reusable too, for a pipeline that stands an estate up and
tears it back down. The caller must repeat the registry name in full — there are
no defaults on `acr_name` or `confirm` on this path, so a `uses:` line cannot
delete a registry by accident:

```yaml
jobs:
  destroy-acr:
    uses: rubensgomes-org/azure-iac/.github/workflows/acr-destroy.yml@main
    with:
      environment_name: dev                 # optional; defaults to dev
      acr_name: rubensdevacr                # required; no default
      confirm: DESTROY ACR rubensdevacr     # required; must match exactly
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
      AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

Two things will block a caller that has not been set up for this on purpose:

- The calling repository must define a GitHub Environment named **`AZURE`**,
  because the destroy job binds one and that binding resolves caller-side. Its
  Environment secrets can supply the four credentials, in which case the
  `secrets:` block above is optional.
- `github.actor` on the called run is whoever triggered the *caller's* run, and
  the actor allowlist is enforced there too. A push by anyone else, or a
  scheduled or bot-triggered upstream run, is denied before any credential is
  used.

Running the same thing by hand, plus cost, teardown, and the safety notes, is
covered in [PROVISION_ACR.md](./PROVISION_ACR.md).

### Static analysis (SonarCloud)

`release.yml` runs a SonarCloud scan before it publishes anything, and **fails
the run if the quality gate is red**. Configuration lives in
[`sonar-project.properties`](./sonar-project.properties) at the repo root — the
workflow passes no scanner arguments of its own, so changing analysis scope
means editing that file, not the workflow.

Every PR is gated on the same scan by `pr-verify.yml`, so a red gate blocks the
merge before a tag exists. `make sonar` runs it locally (Docker + `SONAR_TOKEN`)
but is **not** part of the release recipe — it is a fallback for reproducing a
CI Sonar failure, and on Apple Silicon it is very slow, since the scanner image
is amd64-only and blames through JGit.

Pull requests are scanned in PR mode by `pr-verify.yml`, and the tag build is
scanned as `main` by `release.yml`. The branch name is therefore passed by each
caller rather than pinned in `sonar-project.properties` — pinning it would make
every PR analysis overwrite main's.

Accepted findings are suppressed in `sonar-project.properties` with
`sonar.issue.ignore.multicriteria`, never marked "Accepted" in the SonarCloud
UI — an exemption that lives in the repo is greppable, reviewable in a diff, and
carries its reason in a comment beside it. Each one is pinned to an exact file
path so a new module raising the same rule still gets flagged.

Two things must be true on the SonarCloud side, and neither is visible from the
repo:

- **Automatic Analysis must stay disabled** for the project (Administration →
  Analysis Method). It is mutually exclusive with CI-based analysis; with both
  on, every CI scan fails.
- `SONAR_TOKEN` is an organization Actions secret on `rubensgomes-org`, shared
  with this repository.

## Working on this project

Two flows: shipping a change, and cutting a release. Both go through a pull
request — `main` is protected and accepts nothing else.

### Starting new work

```bash
# 1. Always start from a current main.
git switch main && git pull

# 2. Branch. Prefixes in use: feat/ fix/ docs/ chore/
#    (release/ is reserved — see "Cutting a release" below).
git switch -c feat/<short-name>

# 3. Work. Before pushing, run what the terraform check will run:
make fmt          # rewrites; the CI check is fmt -check and will fail on drift
make validate     # all twelve module roots, no cloud calls

# 4. Record the change under [Unreleased] in CHANGELOG.md, then commit.
git add -A && git commit

# 5. Push and open the PR. The template prompts for the changelog entry
#    and the infra-impact level.
git push -u origin feat/<short-name>
gh pr create --fill

# 6. Wait for terraform + workflows + sonar to pass, then squash-merge.
gh pr merge --squash --delete-branch

# 7. Back to main, and drop the local branch (the remote one deletes itself).
git switch main && git pull
git branch -D feat/<short-name>
```

Four things worth knowing before the first time:

- **Nothing stops you committing to local `main`.** Branch protection only
  applies at push time, so a forgotten `git switch -c` shows up as a rejected
  push after several commits, not as an early warning. Recovering is
  `git switch -c feat/<name>` followed by `git branch -f main origin/main`, but
  branching first is cheaper.
- **Write the `CHANGELOG.md` entry in the same PR.** `make release-check`
  refuses to cut a release on an empty `[Unreleased]`, so it has to happen
  eventually — and it is far easier now than reconstructed from `git log` at
  release time.
- **Do not run `make sonar`.** The `sonar` check on your PR does the same scan
  natively in seconds. The local target is a slow fallback for reproducing a CI
  failure; on Apple Silicon it takes minutes.
- **If the PR touches Terraform, fill in the *Infra impact* box honestly.** It
  is what decides whether the next release is MAJOR, MINOR or PATCH under this
  repo's infra-impact semver.

### Cutting a release

A release is an ordinary PR that happens to bump `VERSION` and roll the
changelog, followed by a tag.

```bash
# 1. Current main, and see what each bump level would produce.
git switch main && git pull
make version && make release-check

# 2. Branch — the name must start with release/ or step 3 refuses to run.
git switch -c release/v0.4.1

# 3. Bump. Writes VERSION, rolls [Unreleased] into a dated section, commits.
#    Does NOT tag.
make release-prep-patch        # or release-prep-minor / release-prep-major

# 4. PR it, exactly like any other change.
git push -u origin release/v0.4.1
gh pr create --title "release: v0.4.1" --fill
gh pr merge --squash --delete-branch

# 5. Tag main's real tip, now that the release commit is on it.
git switch main && git pull
make release-tag

# 6. Publish. Fires release.yml, which re-runs the checks and creates the
#    GitHub Release.
make release-push
```

**The tag is created after the merge, and that ordering is load-bearing.** A
squash-merge rewrites the commit SHA, so a tag made before merging would point
at a commit `main` never sees. You do not have to remember this:
`release-prep-*`
refuses to run anywhere but a `release/*` branch, and `release-tag` refuses to
run anywhere but `main`.

`make release-patch|minor|major` no longer exist — they bumped, committed *and*
tagged in one shot, which cannot work when `main` is PR-only. They fail with a
pointer to the recipe above.

Full detail, including what each semver level means for infrastructure and how
to undo a release at each stage, is in [RELEASING.md](./RELEASING.md).

## Branching

The model behind the commands in
[Working on this project](#working-on-this-project).

`main` is protected and **PR-only**. Nothing is pushed to it directly — every
change, releases included, goes through a pull request whose checks pass.

Merges are **squash only**, and the branch is deleted automatically. That keeps
`main` linear — one commit per PR — which is what makes tagging a release
straightforward.

Every PR is gated by [`pr-verify.yml`](./.github/workflows/pr-verify.yml), which
runs three independent checks:

| Check       | What it does                                                                                          |
|-------------|-------------------------------------------------------------------------------------------------------|
| `terraform` | `terraform fmt -check` and `make validate` across all twelve module roots                             |
| `workflows` | Every workflow file parses, and no GitHub expression is interpolated inside a `run:` body (see below) |
| `sonar`     | SonarCloud analysis in PR mode — findings decorate the diff, and a red quality gate blocks the merge  |

No approval is required, because a solo maintainer cannot approve their own PR;
the checks are the gate. The PR requirement itself is what stops an accidental
push to `main`.

**A note on that `workflows` check.** A `${{ ... }}` expression written inside a
`run:` body is substituted as raw text before the shell parses it, so a crafted
input can execute on the runner. Bind it to an `env:` key and reference `"$VAR"`
instead. This repo had nine such findings, all in the guards protecting its two
destroy workflows; the check exists so they do not come back.

## Releases

Every release is a `MAJOR.MINOR.PATCH` git tag on `main`. The repo-root
`VERSION` file is the source of truth; the tag is `v<VERSION>`, and every Azure
resource in the estate carries a matching `release` tag so you can tell from the
portal which release provisioned it.

Releases are manual — you choose the bump level. The commands are in
[Cutting a release](#cutting-a-release); this section is what they mean.

Nothing is published until `release-push`. Before the release PR merges a
mistake is just a closed PR; after it merges but before the push, it is a
`git tag -d` away. See [RELEASING.md](./RELEASING.md) → Undoing a release.

What MAJOR / MINOR / PATCH mean for infrastructure — the question is what
`terraform plan` does to an already-applied estate, not what an API looks like —
plus the full procedure and the undo path are in
[RELEASING.md](./RELEASING.md). The design rationale is
[§16 of the provisioning plan](./docs/PROVISIONING_PLAN.md).

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
