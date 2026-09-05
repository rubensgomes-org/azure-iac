# azure-iac

An IaC (Infrastructure as Code) project to demonstrate the use of CICD GitHub
Actions workflows and Terraform to init/plan/create/destroy several
infrastructure resources (resource groups, networking, log analytics, managed
identities, key vault, container registry, storage, service bus, PostgreSQL, a
container app environment, container apps, and monitoring) in Azure Cloud.

## Authorship and License

This is a personal project authored and maintained by
[Rubens Gomes](https://rubensgomes.com/)
at [rubensgomes-org/azure-iac](https://github.com/rubensgomes-org/azure-iac).

The project is licensed under the [MIT License](./LICENSE).

## AI-Assisted Development

See [NOTICE](./NOTICE) and [AI_DISCLAIMER.md](./AI_DISCLAIMER.md) about
AI-assisted code and documentation generation.

## Pre-requisites

The following pre-requisites are required:

- Microsoft Azure account with an "Owner" `Subscription ID`
- GitHub account
- UNIX OS (e.g., AIX, Linux, macOS, Solaris)
- Azure CLI 2.90+
- Terraform 1.16+
- gh 2.99+, git 2.55+, make 3.8+

## Service Principal and Environment Configuration

The authentication of Terraform against Azure is based on using an Azure
"Service Principal" and a "Service Principal Secret".

The steps in [INITIAL_SETUP](terraform/INITIAL_SETUP.md)
should be initially followed and executed to ensure proper creation of a
"Service Principal" account, assignment of roles, registration of Azure Resource
Providers, and configuration of shell environment variables, and GitHub
Repository Action Secrets and Variables.

## Terraform Bootstrap Backend Configuration

Prior to provisioning any resource in Azure, `Terraform` requires some backend
resources (e.g., Resource Group, Storage Account, and Storage Blob Container)
to be provisioned in Azure. These resources are needed for `Terraform` to
persist State information in Azure cloud.

Follow the steps in
[TF_BOOTSTRAP_CREATE.md](terraform/bootstrap-backend/TF_BOOTSTRAP_CREATE.md).

## Tearing Everything Down

Follow the instructions in [TEARDOWN.md](./terraform/TEARDOWN.md) to completely
destroy both the Azure infrastructure estate and the Terraform bootstrap backend
resources provisioned by this project.

## GitHub Actions

| Workflow                                                 | Shows in Actions as        | Trigger                              | What it does                                                                                                                                                                                        |
|----------------------------------------------------------|----------------------------|--------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`acr-create.yml`](./.github/workflows/acr-create.yml)   | **ACR Create (reusable)**  | `workflow_call`, `workflow_dispatch` | Applies modules 01 → 04 → 06 so a registry exists and is writable. Publishes `acr_name` / `acr_login_server` outputs.                                                                               |
| [`acr-destroy.yml`](./.github/workflows/acr-destroy.yml) | **ACR Destroy (reusable)** | `workflow_call`, `workflow_dispatch` | Destroys module 06 only — the registry and every image in it. The shared UAMI and the resource groups are left standing. Actor-restricted and type-to-confirm guarded.                              |
| [`main-verify.yml`](./.github/workflows/main-verify.yml) | **Main Verify**            | `workflow_dispatch`                  | Checks on `main`: `terraform` and `workflows` always, `sonar` only when the `run_sonar` input is true. Manual only — nothing runs it automatically.                                                 |
| [`release.yml`](./.github/workflows/release.yml)         | **Release (tag push)**     | tag `v*.*.*`, `workflow_dispatch`    | Validates the tag against `VERSION` + `CHANGELOG.md`, runs `fmt`/`validate`, publishes a GitHub Release. The SonarCloud quality gate is opt-in via the `run_sonar` input and skipped on a tag push. |

## Working on this project

Two flows: shipping a change, and cutting a release. Both happen directly on
`main`: this repo is trunk-based, with no feature branches and no PRs.

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

Two things worth knowing before the first time:

- **Pull before you commit, always.** Nothing serialises writers here. `make
  release-check` refuses to run when `HEAD` does not contain `origin/main`, but
  that is a release-time backstop, not day-to-day protection.
- **Write the `CHANGELOG.md` entry as you go.** `make release-check` refuses to
  cut a release on an empty `[Unreleased]`, so it has to happen eventually — and
  it is far easier now than reconstructed from `git log` at release time.

### Cutting a release

A release bumps `VERSION`, rolls the changelog, commits and tags — one command —
and then publishes with a second.

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


---
Author:  [Rubens Gomes](https://rubensgomes.com/)
