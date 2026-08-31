# Project Summary — azure-iac

A quick-reference overview of this project and how to tear the whole estate
down. For the authoritative, exhaustive detail see
[`PROVISIONING_PLAN.md`](./PROVISIONING_PLAN.md); this file is the short version.

## What it is

A **learning-playground Azure Infrastructure-as-Code project** built with
Terraform. It provisions a complete Azure estate to host Java 25 / Spring Boot
4.1.x microservices in Azure Container Apps. The defining architectural theme is
**passwordless authentication everywhere**, via a single shared User-Assigned
Managed Identity (UAMI).

## Architecture at a glance

**5 lifecycle-aligned resource groups:**

| RG                     | Contains                            |
|------------------------|-------------------------------------|
| `rg-dev-platform`      | Managed identities, Key Vault, ACR  |
| `rg-dev-network`       | VNet, subnets, NSGs, private DNS    |
| `rg-dev-data`          | PostgreSQL, Service Bus, Storage    |
| `rg-dev-app`           | Container App Environment + Apps    |
| `rg-dev-observability` | Log Analytics, App Insights, Action Groups |

**12 modules applied in strict dependency order** (01 → 12, destroyed 12 → 01),
each with its **own Terraform state file** under one shared `tfstate` container.
Numeric prefixes encode order; state keys drop the number. Modules read upstream
outputs via `data.terraform_remote_state` — no `-target` needed.

```
01 resource-groups → 02 networking → 03 log-analytics → 04 managed-identities →
05 key-vault → 06 acr → 07 storage → 08 service-bus → 09 postgresql →
10 container-app-environment → 11 container-apps → 12 monitoring
```

## The passwordless model

One UAMI (`id-dev-app`) is attached to every microservice and is the sole auth
principal for everything:

- **PostgreSQL** → via Microsoft Entra (Entra-only auth, no SQL password exists)
- **Blob Storage** → Azure RBAC (`shared_access_key_enabled = false`)
- **Service Bus** → RBAC (no SAS keys)
- **ACR** → `AcrPull` (passwordless image pull)
- **Key Vault** → `Key Vault Secrets User`

Apps use `DefaultAzureCredential` — no passwords, keys, SAS, or connection
strings anywhere in state or app config. Trade-off: shared blast radius across
all apps (acceptable for a playground).

## Repo layout

- `terraform/bootstrap-backend/` — the state backend (`rg-tfstate`,
  `sttfstaterubens01`, `tfstate` container), plus `INITIAL_SETUP.md`,
  `TF_PROVISION.md` and `TF_DESTROY.md`. Not touched by the estate destroy.
- `terraform/modules/<name>/` — reusable child modules (no state/backend)
- `terraform/envs/dev/<NN-module>/` — per-module roots, each with its own state key
- `terraform/envs/dev/{env.tfvars, backend.hcl}` — shared config
- `docs/PROVISIONING_PLAN.md` — the master plan (naming conventions, per-module
  command reference §13, passwordless wiring §12)
- `Makefile` — whole-estate + per-module `apply`/`destroy`/`reprovision`
- `.github/workflows/` — five workflows: `acr-create.yml` / `acr-destroy.yml`
  (both `workflow_call` + `workflow_dispatch`), `release.yml`, `main-verify.yml`,
  and `mirror-push.yml`. Only the two Azure-touching ones hold credentials;
  `release.yml`, `main-verify.yml` and `mirror-push.yml` do not. The Terraform
  ones each shell out to repo-root `make` targets. The state backend has no CI,
  deliberately — create and destroy are hand-operated
  (`terraform/bootstrap-backend/TF_PROVISION.md` and `TF_DESTROY.md`).
  See README.md
- `PROVISION_ACR.md` — standalone runbook for standing up just the ACR
  (modules 01 → 04 → 06) and tearing it back down
- `RELEASING.md` — what MAJOR/MINOR/PATCH mean here and how a tag is cut
- `sonar-project.properties` — SonarCloud scanner config, read unmodified by
  both `release.yml` and `make sonar`. A red quality gate blocks the release

## Auth model (Terraform → Azure)

Terraform authenticates via **Service Principal + client secret** through
environment variables — never in `.tf`/`.tfvars`:

```bash
export ARM_CLIENT_ID=<sp-app-id>
export ARM_CLIENT_SECRET=<sp-secret>
export ARM_TENANT_ID=<tenant-id>
export ARM_SUBSCRIPTION_ID=<subscription-id>
```

## Region

A single `location` in `terraform/envs/dev/env.tfvars` drives all twelve
modules, with no per-module overrides. Before moving the estate to another
region, check it with `az postgres flexible-server list-skus --location
<region>` — the subscription is offer-restricted from provisioning PG Flexible
Server in some regions, and a restricted one forces a per-module override back
into the estate.

The Terraform state backend's region is set independently and is cosmetic: the
azurerm backend addresses state by resource group + storage account + container
name and has no region field, so its location is unrelated to the resources it
tracks.

## Provisioning order

`make apply` from the repo root, or module-by-module in numeric order. A module
whose upstreams are not applied fails at plan with *Unsupported attribute*,
which does not name the real cause. ACR alone is `make apply-resource-groups &&
make apply-managed-identities && make apply-acr`; Container Apps needs 01, 04,
06, 07, 08, 09, 10, then 11.

A rebuild starts with the state backend, not module 01 — until it exists, no
module root can `terraform init`. See
`../terraform/bootstrap-backend/TF_PROVISION.md`, then `terraform init
-reconfigure` each root, then `make apply`. PROVISIONING_PLAN.md §4 has the
dependency map.

## Branching

Trunk-based: `main` is the only branch, every change is committed straight to
it, and there are no feature branches or pull requests. `main-verify.yml` runs
`terraform` and `workflows`, plus `sonar` when its `run_sonar` input is set
true, but is `workflow_dispatch`-only — nothing verifies `main` automatically,
so `make fmt` and `make validate` before committing is the real gate.

## Releases

Tagged `v<VERSION>` off `main`; `VERSION` at the repo root is the source of
truth and every Azure resource carries a matching `release` tag. Semver here is
infra-impact based — see `RELEASING.md`. A release is `make release-<level>`
(bump, changelog roll, commit and tag, all local) followed by
`make release-push`.


## Notable gotchas

- **PostgreSQL bootstrap** uses a `null_resource` + `psql` path (Option B), *not*
  `cyrilgdn/postgresql`, because only `pgaadauth_create_principal` produces
  login-capable AAD roles. That step currently runs manually from Azure Cloud
  Shell because the runner's ISP blocks outbound TCP 5432.
- **Key Vault** dev toggles (`purge_protection = false`) need no manual purge —
  the provider's `purge_soft_delete_on_destroy` defaults to `true` and purges
  during destroy. A manual `az keyvault purge` afterwards returns
  `DeletedVaultNotFound`, which means it already worked.
- **Destroy order matters** — delegated subnets (`snet-app`, `snet-pg`) refuse
  teardown while their delegated resources exist.
- **Azure litters an action group** (`Application Insights Smart Detection`)
  into `rg-dev-observability`; it blocks module 01's RG delete every teardown.
  `make destroy` sweeps it automatically. See PROVISIONING_PLAN §15.

---

# Destroying the infrastructure

The `Makefile` automates the entire teardown in the correct order, including the
post-destroy cleanup.

## The one command

From the repo root:

```bash
make destroy
```

`make destroy` walks all 12 modules in **reverse dependency order** (12 → 01),
then runs the two cleanup steps the plan requires:

1. **Destroys 12 → 01** — monitoring → container-apps → CAE → postgresql →
   service-bus → storage → acr → key-vault → managed-identities → log-analytics →
   networking → resource-groups. Reverse order matters because delegated subnets
   (`snet-app`, `snet-pg`) refuse teardown while Container Apps / PG still exist.
2. **Sweeps Azure-generated orphans** — deletes the
   `Application Insights Smart Detection` action group just before module 01,
   since Terraform never owned it and it blocks the RG delete.
3. **Verifies the Key Vault is gone** — the provider already purges it during
   destroy (`purge_soft_delete_on_destroy` defaults to `true`), so this only
   purges if a soft-deleted vault is genuinely still present.

## Prerequisites before running

1. **Export the SP credentials** (the Makefile assumes these are set):

   ```bash
   export ARM_CLIENT_ID=<sp-app-id>
   export ARM_CLIENT_SECRET=<sp-secret>
   export ARM_TENANT_ID=<tenant-id>
   export ARM_SUBSCRIPTION_ID=<subscription-id>
   ```

2. **Have `az` CLI logged in / available** — the KV purge and PG soft-delete
   report shell out to `az`. If it's not authenticated, those final two steps
   fail (but the destroy itself will have completed).

## Things to be aware of

- **It's `-auto-approve`.** `make destroy` does not prompt per module. To review
  first, destroy one module at a time with `make destroy-<name>` going 12 → 01,
  or run `terraform plan -destroy` manually.
- **PG name stays reserved ~7 days** — and there is no az command to list
  dropped servers (`--show-deleted` is not a real flag). It does not matter:
  the server is named `psql-<env>-<random_id>`, so a fresh apply gets a new
  name and never collides. `az postgres flexible-server revive-dropped`
  recovers one if you ever need it back.
- **The state backend is left intact** (`rg-tfstate`, `sttfstaterubens01`).
  `make destroy` only tears down the estate, not the bootstrap — so you can
  reprovision later with `make apply`.

## One module at a time (reverse order)

The per-module targets do **not** run the KV purge — only the whole-estate
`make destroy` does — so purge the vault manually after `destroy-key-vault`.

```bash
make destroy-monitoring
make destroy-container-apps
make destroy-container-app-environment
make destroy-postgresql
make destroy-service-bus
make destroy-storage
make destroy-acr
make destroy-key-vault      # provider auto-purges; no manual purge needed
make destroy-managed-identities
make destroy-log-analytics
make destroy-networking
make destroy-resource-groups
```

## Reprovision

To tear down and rebuild in one step:

```bash
make reprovision   # = make destroy, then make apply
```

Both steps are idempotent modulo the soft-delete windows on Key Vault, Storage,
Log Analytics, and PostgreSQL.
