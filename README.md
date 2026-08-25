# azure-iac

A playground project to demonstrate the use of IaC (e.g. Terraform) and CICD
pipelines (e.g., GitHub Actions Workflow)  to plan/create/destroy several
infrastructure resources (e.g., resource group, storage account, networking,
app configuration, container registry, container app, blob storage, service
bus, and database) in Azure Cloud.

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

This steps is done only once. It creates the following base resources
required by Terraform:

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

Four workflows live in [`.github/workflows/`](./.github/workflows/). Three of
them authenticate to Azure with the same `terraform-sp` Service Principal used
locally; `release.yml` deliberately holds no Azure credentials.

| Workflow | Trigger | What it does |
| --- | --- | --- |
| [`provision-acr.yml`](./.github/workflows/provision-acr.yml) | `workflow_call`, `workflow_dispatch` | Applies modules 01 → 04 → 06 so a registry exists and is writable. Publishes `acr_name` / `acr_login_server` outputs. |
| [`terraform-bootstrap-apply.yml`](./.github/workflows/terraform-bootstrap-apply.yml) | `workflow_dispatch` | Creates/updates the state backend (`rg-tfstate`, `sttfstaterubens01`, `tfstate`). |
| [`terraform-bootstrap-destroy.yml`](./.github/workflows/terraform-bootstrap-destroy.yml) | `workflow_dispatch` | Tears the state backend down. |
| [`release.yml`](./.github/workflows/release.yml) | tag `v*.*.*` | Validates the tag against `VERSION` + `CHANGELOG.md`, publishes a GitHub Release. |

### Provisioning the ACR from an application pipeline

`provision-acr.yml` is a **reusable** workflow. An application repository calls
it and gates its image push on the result, so the registry hostname is never
hardcoded on the application side:

```yaml
jobs:
  provision-acr:
    uses: rubensgomes-org/azure-iac/.github/workflows/provision-acr.yml@main
    with:
      environment_name: dev          # optional; defaults to dev
    secrets:
      AZURE_CLIENT_ID:       ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_CLIENT_SECRET:   ${{ secrets.AZURE_CLIENT_SECRET }}
      AZURE_TENANT_ID:       ${{ secrets.AZURE_TENANT_ID }}
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
and must be **shared with the calling repository**. Pass them explicitly
rather than using `secrets: inherit` — this SP has subscription-wide write
access, and the explicit list is the only record of which credentials cross a
repo boundary.

Running the same thing by hand, plus cost, teardown, and the safety notes, is
covered in [PROVISION_ACR.md](./PROVISION_ACR.md).

## Releases

Every release is a `MAJOR.MINOR.PATCH` git tag on `main`. The repo-root
`VERSION` file is the source of truth; the tag is `v<VERSION>`, and every
Azure resource in the estate carries a matching `release` tag so you can tell
from the portal which release provisioned it.

Releases are manual — you choose the bump level:

```bash
make release-check     # preflight; shows what each bump would produce
make release-minor     # bump, roll CHANGELOG.md, commit, tag — all LOCAL
make release-push      # push main + the tag; fires .github/workflows/release.yml
```

Nothing leaves your machine until `release-push`, so a mistake is a
`git tag -d` and a `git reset --hard HEAD~1` away.

What MAJOR / MINOR / PATCH mean for infrastructure — the question is what
`terraform plan` does to an already-applied estate, not what an API looks
like — plus the full procedure and the undo path are in
[RELEASING.md](./RELEASING.md). The design rationale is
[§16 of the provisioning plan](./docs/PROVISIONING_PLAN.md).

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
