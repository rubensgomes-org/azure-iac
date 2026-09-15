[![AI Assisted](https://img.shields.io/badge/AI--Assisted-Development-007ACC?logo=openai&logoColor=white)](./AI_DISCLAIMER.md)

# azure-iac

An IaC (Infrastructure as Code) project to demonstrate the use of CICD GitHub
Actions workflows and Terraform to init/plan/create/destroy several
infrastructure resources (resource groups, networking, log analytics, managed
identities, key vault, container registry, storage, service bus, PostgreSQL, a
container app environment, container apps, and monitoring) in Azure Cloud.

## AI Disclaimer

This project includes code and documentation created with the assistance of AI
tools. For details on usage, limits, and review practices, please see
the [AI_DISCLAIMER](./AI_DISCLAIMER.md).

## Installation

To use this project, ensure that your environment is properly configured and
that the required tools are installed.

### Prerequisites

The following prerequisites are required:

- Microsoft Azure account
- An active Azure subscription
- An Azure RBAC role that allows you to create the resources, such as resource
  groups, container registry, container apps, and databases.
- GitHub account
- UNIX-based operating system (for example, AIX, Linux, macOS, or Solaris)
- Azure CLI 2.90+
- Terraform 1.16.0+
- GitHub CLI (`gh`) 2.99+
- Git 2.55+
- GNU Make 3.8+

## Configuration

### Service Principal

The authentication of Terraform against Azure is based on using an Azure
"Service Principal" and a "Service Principal Secret".

The steps in [INITIAL_SETUP](./docs/INITIAL_SETUP.md)
should be initially followed and executed to ensure proper creation of a
"Service Principal" account, assignment of roles, registration of Azure Resource
Providers, and configuration of shell environment variables, and GitHub
Repository Action Secrets and Variables.

### Terraform Bootstrap Backend

Prior to provisioning any resource in Azure, `Terraform` requires some backend
resources (e.g., Resource Group, Storage Account, and Storage Blob Container)
to be provisioned in Azure. These resources are needed for `Terraform` to
persist State information in Azure cloud.

Follow the steps in
[TF_BOOTSTRAP_CREATE](./docs/TF_BOOTSTRAP_CREATE.md).

### Resource Naming

Every resource follows the Microsoft Cloud Adoption Framework form
`<resource type>-<workload>-<environment>` — `rg-rgomesapp-lab`,
`kv-rgomes-lab`, `strgomesapplab`. Two inputs, `workload` and `env`, decide the
whole namespace. See [NAMING](./docs/NAMING.md) for the name table, the
length budgets, and the soft-delete purges a teardown-then-reprovision needs.

### Tearing Everything Down

Follow the instructions in [TEARDOWN](./docs/TEARDOWN.md) to completely
destroy both the Azure infrastructure estate and the Terraform bootstrap backend
resources provisioned by this project.

## GitHub Actions

| Workflow          | Purpose                                                                                                 |
|-------------------|---------------------------------------------------------------------------------------------------------|
| `acr-create.yml`  | apply modules 01 → 04 → 06 so a registry exists and is writable                                         |
| `acr-destroy.yml` | **destructive** — destroy module 06 only, the registry and every image in it                            |
| `destroy-all.yml` | **destructive** — destroy the whole estate, modules 12 → 01; plans only unless `dry_run` is cleared     |
| `main-verify.yml` | manual checks on `main` — `terraform` and `workflows` always, `sonar` when `run_sonar` is true          |
| `release.yml`     | fires on a `v*.*.*` tag push — validate the tag against `VERSION` + `CHANGELOG.md`, publish the release |

## Development Workflow

See [DEVELOPMENT_WORKFLOW](./docs/DEVELOPMENT_WORKFLOW.md) for guidance on
developing, and cutting a release on this project.

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
