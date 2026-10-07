# Azure Infrastructure as Code

[![terraform](https://img.shields.io/badge/terraform-1.16%2B-0969da?logo=terraform)](https://developer.hashicorp.com/terraform)
[![GitHub](https://img.shields.io/badge/GitHub-Actions-0969da?logo=github+actions)](https://github.com/features/actions)
[![Microsoft](https://img.shields.io/badge/Microsoft-Azure-0969da)](https://azure.microsoft.com/en-us)
[![AI](https://img.shields.io/badge/AI-Assisted-d29922?logo=claude+code)](https://github.com/rubensgomes-org/azure-iac/blob/main/AI_DISCLAIMER.md)
[![license](https://img.shields.io/badge/license-MIT-1a7f37)](https://github.com/rubensgomes-org/azure-iac/blob/main/LICENSE)

An IaC (Infrastructure as Code) project to demonstrate the use of CI/CD GitHub
Actions workflows and Terraform to init/plan/create/destroy several
infrastructure resources (resource groups, networking, log analytics, managed
identities, key vault, container registry, storage, service bus, PostgreSQL, a
container app environment, container apps, and monitoring) in Azure.

---

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
- An Azure RBAC role that allows you to create resources such as resource
  groups, container registries, container apps, and databases.
- GitHub account
- Azure CLI 2.90+
- Terraform 1.16.0+
- GitHub CLI (`gh`) 2.99+
- Git 2.55+
- GNU Make 3.8+

## Configuration

### Service Principal

The authentication of Terraform against Azure is based on using an Azure
"Service Principal" and a "Service Principal Secret".

Follow the steps in [INITIAL_SETUP](./docs/INITIAL_SETUP.md) to create the
"Service Principal" account, assign roles, register Azure Resource Providers,
and configure shell environment variables and GitHub Repository Action Secrets
and Variables.

### Terraform Bootstrap Backend

Prior to provisioning any resource in Azure, `Terraform` requires some backend
resources (e.g., Resource Group, Storage Account, and Storage Blob Container)
to be provisioned in Azure. These resources are needed for `Terraform` to
persist state information in Azure.

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

| Workflow             | Purpose                                                                                                 |
|----------------------|---------------------------------------------------------------------------------------------------------|
| `acr-create.yml`     | apply modules 01 → 04 → 06 so a registry exists and is writable                                         |
| `acr-destroy.yml`    | **destructive** — destroy module 06 only, the registry and every image in it                            |
| `cae-create.yml`     | apply modules 01 → 02 → 03 → 10 so a Container App Environment exists                                   |
| `cae-destroy.yml`    | **destructive** — destroy module 10 only, the Container App Environment                                 |
| `aca-create.yml`     | apply modules 01 → 02 → 03 → 04 → 05 → 06 → 10 → 11 so the Container Apps exist                         |
| `aca-destroy.yml`    | **destructive** — destroy module 11 only, the Container Apps                                            |
| `rg-create-all.yml`  | apply module 01, all six resource groups; plans only unless `dry_run` is cleared                        |
| `rg-destroy-all.yml` | **destructive** — destroy module 01 only, after modules 02–12; plans only unless `dry_run` is cleared   |
| `destroy-all.yml`    | **destructive** — destroy the whole estate, modules 12 → 01; plans only unless `dry_run` is cleared     |
| `main-verify.yml`    | manual checks on `main` — `terraform` and `workflows` always, `sonar` when `run_sonar` is true          |
| `release.yml`        | fires on a `v*.*.*` tag push — validate the tag against `VERSION` + `CHANGELOG.md`, publish the release |

## Open Source Project Information

This project is open source and publicly hosted on GitHub at
[rubensgomes-org](https://github.com/rubensgomes-org/). It is
published under an
[OSI-approved open-source license](https://opensource.org/licenses).

> **Note:** Public availability and the use of an OSI-approved license are
> requirements for eligibility to
> use [SonarQube Cloud](https://sonarcloud.io/) under its free plan for
> open-source projects.

## License

This project is licensed under the
[MIT License](https://github.com/rubensgomes-org/azure-iac/blob/main/LICENSE).

## Links

- [GitHub Project](https://github.com/rubensgomes-org/azure-iac)
- [Development Workflow](https://github.com/rubensgomes-org/azure-iac/blob/main/docs/DEVELOPMENT_WORKFLOW.md)
- [Initial Setup](https://github.com/rubensgomes-org/azure-iac/blob/main/docs/INITIAL_SETUP.md)
- [Miscellaneous](https://github.com/rubensgomes-org/azure-iac/blob/main/docs/MISC.md)
- [Modules Dependency](https://github.com/rubensgomes-org/azure-iac/blob/main/docs/MODULES_DEPENDENCY.md)
- [IaC Naming](https://github.com/rubensgomes-org/azure-iac/blob/main/docs/NAMING.md)
- [IaC Consumption Pricing](https://github.com/rubensgomes-org/azure-iac/blob/main/docs/PRICING.md)
- [IaC Teardown](https://github.com/rubensgomes-org/azure-iac/blob/main/docs/TEARDOWN.md)
- [Terraform Bootstrap Create](https://github.com/rubensgomes-org/azure-iac/blob/main/docs/TF_BOOTSTRAP_CREATE.md)
- [Terraform Bootstrap Destroy](https://github.com/rubensgomes-org/azure-iac/blob/main/docs/TF_BOOTSTRAP_DESTROY.md)

---
Author: [Rubens Gomes](https://rubensgomes.com/)
