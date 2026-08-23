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

- `terraform/bootstrap-backend/` — the already-provisioned state backend
  (`rg-tfstate`, `sttfstaterubens01`, `tfstate` container). Not torn down by the
  estate destroy.
- `terraform/modules/<name>/` — reusable child modules (no state/backend)
- `terraform/envs/dev/<NN-module>/` — per-module roots, each with its own state key
- `terraform/envs/dev/{env.tfvars, backend.hcl}` — shared config
- `docs/PROVISIONING_PLAN.md` — the master plan (naming conventions, per-module
  command reference §13, passwordless wiring §12)
- `Makefile` — whole-estate + per-module `apply`/`destroy`/`reprovision`

## Auth model (Terraform → Azure)

Terraform authenticates via **Service Principal + client secret** through
environment variables — never in `.tf`/`.tfvars`:

```bash
export ARM_CLIENT_ID=<sp-app-id>
export ARM_CLIENT_SECRET=<sp-secret>
export ARM_TENANT_ID=<tenant-id>
export ARM_SUBSCRIPTION_ID=<subscription-id>
```

## Status (paused, updated 2026-07-26)

**Feature-complete in code.** All 12 modules are implemented, and all have been
applied and verified against Azure; `make validate` passes across every root.
The user runs all `terraform` / `make` commands manually.

**Live in Azure right now: every module except 11-container-apps.**
`make destroy-container-apps` was run on 2026-07-26, so `rg-dev-app` contains
only the Container App Environment (`cae-dev`) and the `container-apps` state
key is empty. Nothing downstream depends on the apps — module 12's diagnostic
settings target KV, ACR, Storage, Service Bus, and PostgreSQL. Restore with
`make apply-container-apps`; every upstream module is still standing.

**Deferred / outstanding work:**

- **D1** — set a real image for module 11 (it last ran the
  `mcr.microsoft.com/k8se/quickstart` placeholder) once real Spring Boot images
  are pushed to ACR *(blocked on app dev)*. Since 11 is destroyed, this is a
  fresh `make apply-container-apps` with `apps_image_map` set
- **D2** — wire `APPLICATIONINSIGHTS_CONNECTION_STRING` into Container Apps
  *(depends on D1)*
- **D3** — replace the manual PG data-plane bootstrap with a Container Apps Job
  (§12a)
- **D4** — APIM, always-deferred iteration-2 work

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
