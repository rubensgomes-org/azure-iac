# azure-iac

A playground project to demonstrate the use of IaC (e.g. Terraform) and CICD
pipelines (e.g., GitHub Actions Workflow)  to plan/create/destroy several
infrastructure resources (e.g., resource group, storage account, networking, app
configuration, container registry, container app, blob storage, service bus, and
database) in Azure Cloud.

**Making a change?** Start at
[Working on this project](#working-on-this-project) — this repo is trunk-based,
so you commit straight to `main`.

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
in [INITIAL_SETUP](terraform/bootstrap-backend/INITIAL_SETUP.md) before running with the Phase 0
below.

### Bootstrap Terraform Backend Module (bootstrap-backend)

This steps is done only once. It creates the following base resources required
by Terraform:

- Terraform Resource group
- Terraform Storage account
- Terraform Blob Container

It is done **by hand**, not by a workflow. The bootstrap is two-pass — apply on
local state, then `terraform init -migrate-state` to move state into the
container it just created — and the second pass prompts, so there is nothing
useful for CI to do. The runbook is
[`terraform/bootstrap-backend/TF_PROVISION.md`](./terraform/bootstrap-backend/TF_PROVISION.md).
Tearing it back down is the same story; see
[`TF_DESTROY.md`](./terraform/bootstrap-backend/TF_DESTROY.md).

### Tearing everything down

From the repo root, with the `ARM_*` variables exported **and** a separate
`az login` session active (the az CLI does not inherit `ARM_*`):

```bash
make destroy   # walks modules 12 → 01, sweeping Azure-generated orphans
```

Verify with `az group list -o table` — no `rg-dev-*` rows should remain.
`rg-tfstate` and `NetworkWatcherRG` are expected to survive.

See [§15 of the provisioning plan](./docs/PROVISIONING_PLAN.md) for the full
procedure: verification commands, what legitimately survives, and the failure
modes that can make a destroy silently do nothing.

Removing the **state backend** as well is a separate, one-way operation with
its own runbook —
[`terraform/bootstrap-backend/TF_DESTROY.md`](./terraform/bootstrap-backend/TF_DESTROY.md).
There is deliberately no CI workflow for it — a destroy cannot run from inside
the backend it is deleting — nor for the bootstrap that creates it, which is
two-pass and interactive. Both are done by hand; the bootstrap runbook is
[`TF_PROVISION.md`](./terraform/bootstrap-backend/TF_PROVISION.md).

## GitHub Actions

Five workflows live in [`.github/workflows/`](./.github/workflows/). Two of
them authenticate to Azure with the same `terraform-sp` Service Principal used
locally; `release.yml` and `main-verify.yml` deliberately hold no Azure
credentials (their only secret is `SONAR_TOKEN`, which reaches sonarcloud.io and
nothing else), and `mirror-push.yml` holds none either — its only secret is a
PAT for one private repository in a work GitHub namespace.

| Workflow                                                                   | Shows in Actions as        | Trigger                              | What it does                                                                                                                                                                                  |
|----------------------------------------------------------------------------|----------------------------|--------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`acr-create.yml`](./.github/workflows/acr-create.yml)                     | **ACR Create (reusable)**  | `workflow_call`, `workflow_dispatch` | Applies modules 01 → 04 → 06 so a registry exists and is writable. Publishes `acr_name` / `acr_login_server` outputs.                                                                         |
| [`acr-destroy.yml`](./.github/workflows/acr-destroy.yml)                   | **ACR Destroy (reusable)** | `workflow_call`, `workflow_dispatch` | Destroys module 06 only — the registry and every image in it. Resource groups (01) and the shared UAMI (04) are left standing. Actor-restricted and type-to-confirm guarded on both triggers. |
| [`main-verify.yml`](./.github/workflows/main-verify.yml)                   | **Main Verify**            | `workflow_dispatch`                  | Checks on `main`: `terraform` and `workflows` always, `sonar` only when the `run_sonar` input is true. Manual only — nothing runs it automatically. See Trunk-based development.              |
| [`release.yml`](./.github/workflows/release.yml)                           | **Release (tag push)**     | tag `v*.*.*`                         | Validates the tag against `VERSION` + `CHANGELOG.md`, runs `fmt`/`validate` and the SonarCloud quality gate, publishes a GitHub Release.                                                      |
| [`mirror-push.yml`](./.github/workflows/mirror-push.yml)                   | **Mirror Push (work repo)**| `workflow_dispatch`                  | Force-pushes `main` to a private repository in a work GitHub namespace. Manual only, actor-restricted. See Mirroring to the work repository.                                                  |

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

### Mirroring to the work repository

A copy of this repository lives in a private repository inside a work GitHub
Enterprise Managed Users (EMU) namespace:

```text
source   rubensgomes-org/azure-iac       this repo, public
target   rubens-gomes_3CC/azure-iac      work, private
```

[`mirror-push.yml`](./.github/workflows/mirror-push.yml) publishes `main` there.
Run it from the **Actions** tab → **Mirror Push (work repo)** → *Run workflow*,
with the branch selector left on `main`.

It is **manual only**. `push: branches: [main]` is the obvious trigger for a
mirror and is what most examples use; this one deliberately does not, because
mirroring publishes into a corporate namespace and *when* that happens should
stay a decision rather than a side effect of committing.

What it does and does not do:

- Pushes **`main` only**, with `--force`. No tags, no other branches, no
  `--mirror`. The work copy is a reflection of this repo's trunk, not a peer —
  anything committed directly to its `main` is destroyed by the next run. The
  run log records the SHA that was overwritten, because nothing else does.
- Denies the run unless the actor is the allowlisted maintainer **and** the
  dispatch came from `main`. The branch selector accepts any branch, and
  whatever it checks out is what would be force-pushed, so the ref is checked
  rather than assumed.
- Verifies afterwards that the mirror's `main` is at this commit. `git push`
  exits 0 for a no-op and a server-side push rule can accept a push while
  rewriting it, so "the command returned" is not the same claim as "the mirror
  is up to date".

#### The token

One repository-level Actions secret, **`WORK_GITHUB_PAT`** (Settings → Secrets
and variables → Actions). It never touches Azure and no Azure workflow reads it.

Because the target is an EMU namespace, the usual PAT advice does not apply:

- Mint it **while signed in as `rubens-gomes_3CC`** through the enterprise
  identity provider — not from the personal account. A personal-account token
  gets **404**, not 403, on a private EMU repository, which reads as "that repo
  doesn't exist" and sends you looking in entirely the wrong place.
- Prefer a **fine-grained** PAT; EMU enterprises commonly disable classic ones.
  Resource owner = the namespace that owns the repository, repository access =
  only `azure-iac`, and **two** permissions:
  - `Contents: Read and write`
  - `Workflows: Read and write` — **required, and easy to miss.** The commits
    being mirrored include files under `.github/workflows/`, and a token
    without this is rejected with *"refusing to allow a Personal Access Token
    to create or update workflow ..."*. The classic-PAT equivalent is the
    `workflow` scope alongside `repo`.
- A fine-grained PAT may need organization approval before it becomes active,
  and a classic one — if permitted at all — must be **SSO-authorized** for the
  owning organization.

#### Turn Actions off in the work repository

The mirror receives `.github/workflows/` along with everything else, but
nothing in it fires there on a mirror push: every workflow is either
`workflow_dispatch`-only or tag-triggered, and no tags are pushed to the
mirror. `mirror-push.yml`'s own mirrored copy is additionally gated on an actor
name that cannot exist in an EMU namespace, so pressing Run on it there is
denied before it reads a secret. Disable Actions anyway at Settings → Actions →
General → *Disable actions* in the work repository: it costs nothing, and it
means adding a `push:` trigger to a workflow here cannot start failing runs
over there for want of a `SONAR_TOKEN`.

### Static analysis (SonarCloud)

`release.yml` runs a SonarCloud scan before it publishes anything, and **fails
the run if the quality gate is red**. Configuration lives in
[`sonar-project.properties`](./sonar-project.properties) at the repo root — the
workflow passes no scanner arguments of its own, so changing analysis scope
means editing that file, not the workflow.

Nothing scans a commit automatically before you tag it. `main-verify.yml` is
manual, so unless you dispatch it, the tag push is the first time SonarCloud
sees the release commit — and a red gate there leaves a tag with no GitHub
Release. Dispatch `main-verify.yml` with `-f run_sonar=true` (or run
`make sonar`) before cutting a release you care about — the scan is opt-in, so
a bare dispatch skips it. `make sonar` runs the same scan locally (Docker +
`SONAR_TOKEN`), but on Apple Silicon it is very slow, since the scanner image
is amd64-only and blames through JGit; the dispatch is usually the better
option.

All three callers analyse the same branch, so `sonar.branch.name=main` is
pinned in `sonar-project.properties` and none of them passes a scanner argument
of its own. That pin is load-bearing for `release.yml`: it fires on a tag ref,
which would otherwise be submitted as a short-lived branch whose quality gate
this plan cannot read.

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

Two flows: shipping a change, and cutting a release. Both happen directly on
`main` — see [Trunk-based development](#trunk-based-development) for why.

### Starting new work

```bash
# 1. Always start from a current main.
git switch main && git pull

# 2. Work. Before committing, run what the CI checks will run:
make fmt          # rewrites; the CI check is fmt -check and will fail on drift
make validate     # all twelve module roots, no cloud calls

# 3. Record the change under [Unreleased] in CHANGELOG.md, then commit.
git add -A && git commit

# 4. Push. Nothing verifies this automatically — step 2 was the gate.
git push origin main

# 5. Optional: run the same three checks in CI against the pushed commit.
gh workflow run main-verify.yml --ref main && gh run watch
#    Add -f run_sonar=true to include the SonarCloud scan (off by default).
```

Four things worth knowing before the first time:

- **The checks run *after* the push, not before it.** That is the trade this
  model makes. `make fmt && make validate` locally costs about a minute and
  turns almost every red run into one you never saw.
- **Pull before you commit, always.** Nothing serialises writers here. `make
  release-check` refuses to run when `HEAD` does not contain `origin/main`, but
  that is a release-time backstop, not day-to-day protection.
- **Write the `CHANGELOG.md` entry as you go.** `make release-check` refuses to
  cut a release on an empty `[Unreleased]`, so it has to happen eventually —
  and it is far easier now than reconstructed from `git log` at release time.
- **Do not run `make sonar`.** The `sonar` job on the push does the same scan
  natively in seconds. The local target is a slow fallback for reproducing a CI
  failure; on Apple Silicon it takes minutes.

### Cutting a release

A release bumps `VERSION`, rolls the changelog, commits and tags — one command
— and then publishes with a second.

```bash
# 1. Current main, and see what each bump level would produce.
git switch main && git pull
make version && make release-check

# 2. Bump. Writes VERSION, rolls [Unreleased] into a dated section, commits,
#    and creates the annotated tag. All local — nothing is pushed.
make release-patch             # or release-minor / release-major

# 3. Publish. Pushes main, then the tag, which fires release.yml.
make release-push
```

**Nothing leaves the machine until step 3**, which is the whole reason the bump
and the push are separate targets. A mistyped level or a bad changelog roll is
undone with `git tag -d v$(cat VERSION) && git reset --hard HEAD~1`.

Every release target refuses to run anywhere but `main`, and refuses to run on
a dirty tree or when `HEAD` is behind `origin/main`.

Which level to pick is decided by what `terraform plan` would do to an
already-applied estate, not by what the diff looks like. Full detail, plus how
to undo a release at each stage, is in [RELEASING.md](./RELEASING.md).

## Trunk-based development

The model behind the commands in
[Working on this project](#working-on-this-project).

`main` is the only branch. Every change — releases included — is committed
straight to it and pushed. There are no feature branches, no pull requests, and
no branch protection.

That is a deliberate choice for a single-maintainer learning repo, and it is a
trade, not a free simplification. A pull request buys review and a pre-merge
gate; with one maintainer there is nobody to review, so the only thing lost is
the pre-merge gate — and what it cost was a two-phase release, because a
squash-merge rewrites the commit SHA a locally created tag would point at.
Committing on `main` means the SHA you tag is the SHA you push, so a release
collapses back to one command.

The checks that would have run in a PR live in
[`main-verify.yml`](./.github/workflows/main-verify.yml), which is
**`workflow_dispatch`-only — nothing triggers it for you**:

| Check       | What it does                                                                                          |
|-------------|-------------------------------------------------------------------------------------------------------|
| `terraform` | `terraform fmt -check` and `make validate` across all twelve module roots                             |
| `workflows` | Every workflow file parses, and no GitHub expression is interpolated inside a `run:` body (see below) |
| `sonar`     | SonarCloud analysis of `main` — a red quality gate fails the check. **Opt-in:** off unless you set the `run_sonar` input to true |

These are **not** required status checks and cannot be: a dispatch-only
workflow reports against no push at all.

Nothing runs them for you, so **`make fmt && make validate` before committing
is the only thing standing between a broken commit and `main`** — there is no
after-the-fact report either. Dispatch the workflow
(`gh workflow run main-verify.yml --ref main`) when you want the CI versions,
and add `-f run_sonar=true` for the Sonar scan the local commands do not cover
— it is off by default, so a bare dispatch runs `terraform` and `workflows`
only.

The dispatch form lets you pick any branch, but the `sonar` job refuses to run
off `main`: `sonar-project.properties` pins `sonar.branch.name=main`, so a run
from elsewhere would publish that branch's code as main's analysis.

`release.yml` re-runs all three at tag time, and there a red gate genuinely
blocks — no GitHub Release is published over failing analysis.

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

Nothing is published until `release-push`. Up to that point the release commit
and its tag are local, and `git tag -d v$(cat VERSION) && git reset --hard
HEAD~1` puts the tree back exactly as it was. Afterwards, a published tag is
never moved — the fix is the next patch release. See
[RELEASING.md](./RELEASING.md) → Undoing a release.

What MAJOR / MINOR / PATCH mean for infrastructure — the question is what
`terraform plan` does to an already-applied estate, not what an API looks like —
plus the full procedure and the undo path are in
[RELEASING.md](./RELEASING.md). The design rationale is
[§16 of the provisioning plan](./docs/PROVISIONING_PLAN.md).

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
