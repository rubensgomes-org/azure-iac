# CLAUDE.md

Pointer file for Claude Code sessions working on this repo. It carries the
working rules and the map; the detail lives in the documents it points at.

## Working rules

- **This file is read-only.** Propose changes and wait for approval; never edit
  it as a side effect of other work. Durable facts go to `docs/`, dated changes
  to `CHANGELOG.md`.
- **Write only what was asked.** No adjacent sections, anticipated follow-ups,
  or unrequested rationale in documentation. Match the length of the answer
  already given in the terminal; offer a fuller version rather than writing it.
- **The user runs all `terraform` commands.** Never `terraform apply` or
  `terraform destroy` from an agent session.
- **`make fmt` and `make validate` before committing** — no workflow verifies
  `main` automatically, so this is the only gate.
- Check `docs/PROVISIONING_PLAN.md` before any decision spanning modules
  (naming, ordering, RG assignment, auth model).
- Match the style of `terraform/bootstrap-backend/` for new module code — block
  comments explaining "why", not just "what".
- **Trunk-based**: `main` is the only branch. No feature branches, no PRs. Do
  not create one unless asked.

## What this project is

An Azure IaC project. Terraform provisions a fixed set of Azure resources
(Resource Groups, VNet, Log Analytics, Managed Identity, Key Vault, ACR,
Storage, Service Bus, PostgreSQL Flexible, Container App Environment, Container
Apps, Monitoring; APIM deferred to a second iteration). 

## Documentation map

| Document                                                        | What it covers                                                                                         |
|-----------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
| `docs/PROVISIONING_PLAN.md`                                     | The master plan. §12 auth wiring, **§15 the authoritative teardown procedure**, §16 release rationale. |
| `docs/MODULES_DEPENDENCY.md`                                    | Which module depends on which, and why.                                                                |
| `docs/CI.md`                                                    | The four workflows, their credential models and guards. Read before editing any workflow.              |
| `docs/SONAR.md`                                                 | SonarCloud config, the suppression list, and the Automatic Analysis constraint.                        |
| `docs/GOTCHAS.md`                                               | Things that have already cost time. Read when something behaves inexplicably.                          |
| `RELEASING.md`                                                  | Read before touching anything release-related.                                                         |
| `terraform/bootstrap-backend/TF_PROVISION.md` / `TF_DESTROY.md` | Hand-operated backend bootstrap and teardown. No CI for either, deliberately.                          |
| `terraform/bootstrap-backend/INITIAL_SETUP.md`                  | One-time SP creation, provider registration, `ARM_*`.                                                  |
| `PROVISION_ACR.md`                                              | Standalone runbook for modules 01 → 04 → 06.                                                           |

## Repo layout

- `.github/workflows/` — four workflows; see `docs/CI.md`. No composite actions.
- `terraform/bootstrap-backend/` — the state backend module (`rg-tfstate`,
  `sttfstaterubens01`, `tfstate` container). Do not touch unless
  re-bootstrapping.
- `terraform/modules/<name>/` — reusable child modules. No state, no backend.
- `terraform/envs/dev/env.tfvars` — shared env vars (env, location, prefix, apps
  list, tags, PG Entra admin group ID).
- `terraform/envs/dev/backend.hcl` — shared azurerm backend config.
- `terraform/envs/dev/<NN-module>/` — per-module Terraform root, own state key
  `<module>/terraform.tfstate`. Numeric prefix encodes dependency order.

## Provisioning order

**A rebuild starts with the state backend, not with module 01.** Until it
exists, every root's `terraform init -backend-config=../backend.hcl` targets a
Storage Account that is not there.

1. Bootstrap `terraform/bootstrap-backend/` — two passes; see `TF_PROVISION.md`.
2. `terraform init -reconfigure -backend-config=../backend.hcl
   -backend-config="key=<module>/terraform.tfstate"` in each module root.
3. `make apply` from repo root, or module-by-module in numeric order.

Upstreams must be applied first — see `docs/MODULES_DEPENDENCY.md`. A root
pointed at an empty state key fails at plan with *Unsupported attribute*, which
does not name the real cause. Modules apply 01 → 12 and destroy 12 → 01;
`make apply` / `make destroy` drive the whole estate, `make <verb>-<short-name>`
one module. For a full teardown follow `docs/PROVISIONING_PLAN.md` §15.

## Per-module workflow

From `terraform/envs/dev/<NN-module>/`:

```bash
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=<module>/terraform.tfstate"

terraform plan  \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan

# Verify via `az` CLI (module-specific — see the module's README).

terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

## Auth model

Terraform authenticates via **Service Principal + client secret** from the
environment: `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`,
`ARM_SUBSCRIPTION_ID`. **Never** put credentials in `.tf` or `.tfvars`; every
`providers.tf` declares a bare `provider "azurerm" { features {} }` and the
provider picks `ARM_*` up from the environment.

Application runtime auth is **passwordless via the shared UAMI** — see
`docs/PROVISIONING_PLAN.md` §12 for the wiring across PG, Blob, Service Bus, Key
Vault and ACR.

## Releases in brief

Repo-root **`VERSION`** (bare `MAJOR.MINOR.PATCH`) is the single source of
truth; the tag is `v$(cat VERSION)`. Semver is **infra-impact based**: MAJOR =
`plan` destroys/recreates/renames; MINOR = additive; PATCH = in-place only. A
release is two commands from `main` — `make release-patch|minor|major` (local:
bumps, rolls the changelog, commits, tags) then `make release-push`. Read
`RELEASING.md` before anything else release-related.

## Hazards — read the one-liner, then `docs/GOTCHAS.md`

These are the ones that fail *silently* or destructively:

- **Never put `$(MAKE)` inside a multi-command recipe line.** Make runs such a
  line even under `-n`, which once made `make -n destroy` tear down the estate
  for real.
- **No GNU coreutils on macOS.** `tac` returned empty in the destroy loop, which
  iterated zero times and reported success having destroyed nothing. Avoid
  `tac`, `seq`, `timeout`, `readlink -f`, `xargs -r`, `sed -i` without a suffix.
- **Never write `${{ ... }}` inside a workflow `run:` body** — it is substituted
  as raw text and executes on the runner. Bind it to an `env:` key.
- **`make validate` breaks `terraform output`** — it inits with
  `-backend=false`, leaving `.terraform/` pointed at an empty local backend.
- **Destroy order matters** — delegated subnets refuse to destroy while their
  delegated resources exist; container-apps → CAE → PG before networking.
- **Azure litters an action group into `rg-dev-observability`** that blocks
  module 01's RG delete. `make purge-orphans` sweeps it.
- **A failed module aborts `make destroy` entirely.** The loop is idempotent and
  resumable — fix and re-run.
- **A `VERSION` bump makes every module show a pending `~ tags` diff.** Intended
  drift signal, not a bug; clears on the next apply.
