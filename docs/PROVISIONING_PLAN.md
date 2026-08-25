# Iterative Azure IaC Provisioning Plan

## Context

You have a Terraform bootstrap already working: `terraform/bootstrap-backend/`
provisioned the state backend (`rg-tfstate`, `sttfstaterubens01`, `tfstate`
container) and migrated its own state remotely. The 12 module stub directories
under `terraform/modules/` are empty, `terraform/envs/dev/env.tfvars` is empty,
and no `docs/` folder exists yet.

You want to build the rest of the estate one module at a time — apply → verify →
move to the next — with per-module instructions you can run by hand, and
eventually automate provision / destroy / reprovision end-to-end.

**Decisions confirmed:**

- **RG split**: 5 lifecycle-aligned RGs (`platform`, `network`, `data`, `app`,
  `observability`).
- **APIM**: defer to a second iteration.
- **ACR**: add as a module between Key Vault and Storage (needed by Container
  Apps).
- **Plan location**: `docs/PROVISIONING_PLAN.md`.
- **Auth model**: **passwordless everywhere** via a **single shared
  User-Assigned Managed Identity** attached to every microservice in the ACA
  environment. That one UAMI authenticates to PostgreSQL via Microsoft Entra (
  Azure AD), to Blob Storage via Azure RBAC, to Service Bus via RBAC, and pulls
  from ACR via `AcrPull` — no passwords, keys, SAS, or connection strings in any
  app. This is the learning-playground default: less RBAC ceremony than per-app
  identities, still fully passwordless.
- **One database per microservice**, all on the shared PostgreSQL Flexible
  Server. The single shared UAMI is registered once as an AAD principal in PG
  and granted `CONNECT`/schema privileges on every app DB (fanned out via
  `for_each = toset(var.apps)`).

## Progress (as of 2026-08-24)

Modules **01 through 12 are fully implemented, and all have been applied
and verified against Azure at least once** — the estate is
feature-complete in code.

**Currently applied in Azure: module 01 ONLY. Everything else is torn
down.** Verified 2026-08-24: the five resource groups
(`rg-dev-platform`, `-network`, `-data`, `-app`, `-observability`)
exist and are all empty — `az resource list -g <rg>` returns nothing
for any of them. In the `tfstate` container only
`resource-groups/terraform.tfstate` is populated (~10 KB); every other
module's state key is an empty few-hundred-byte shell (serial +
lineage, no resources).

The estate therefore costs $0/month at present: resource groups and the
state Storage Account are free at this scale.

Re-check rather than trusting this note — a status line ages badly:

```bash
az group list --query "[].name" -o tsv
az resource list -g rg-dev-platform -o tsv          # empty => nothing applied
az storage blob list --account-name sttfstaterubens01 \
  --container-name tfstate --auth-mode key \
  --query "[].{name:name,size:properties.contentLength}" -o table
```

`--auth-mode key` is required: the interactive user account holds no
`Storage Blob Data *` role, so `--auth-mode login` fails on that
container.

**Rebuilding** is `make apply` from the repo root (01 no-ops), or
module-by-module in numeric order. Each module's upstreams must be
applied first — a root whose `data.terraform_remote_state` points at an
empty state key fails at plan with *Unsupported attribute*, which is
not a useful message. Two chains worth knowing: ACR alone is
`make apply-managed-identities && make apply-acr` (~$5.07/month, all of
it the Basic registry unit); Container Apps needs 01, 04, 06, 07, 08,
09, 10, then 11.

Module inventory (implementation status — all twelve are written and
have been proven against Azure; see above for what is applied *now*):

- 01-resource-groups
- 02-networking
- 03-log-analytics
- 04-managed-identities
- 05-key-vault
- 06-acr
- 07-storage
- 08-service-bus
- 09-postgresql (data-plane UAMI-principal bootstrap ran from Azure
  Cloud Shell — the in-line `null_resource.pg_bootstrap` is gated OFF
  because the runner's ISP blocks outbound TCP 5432; see the module's
  README "Data-plane bootstrap" section)
- 10-container-app-environment
- 11-container-apps — was deployed with the
  `mcr.microsoft.com/k8se/quickstart:latest` placeholder image on port
  80; swap to real ACR-hosted images via `apps_image_map` +
  `target_port` in the root's `terraform.tfvars` once Spring Boot
  images are pushed — see `11-container-apps/README.md` → "Swapping the
  placeholder image". Since the apps are down, that swap is a re-apply
  rather than an in-place update (see D1) — and note the registry is
  down too, so ACR has to be reprovisioned and the images repushed
  first
- 12-monitoring (App Insights workspace-based on the shared LAW, one
  Action Group with an email receiver, five diagnostic settings sinking
  `allLogs` + `AllMetrics` into the shared LAW from KV, ACR, Storage
  blob subresource, Service Bus, and PostgreSQL)

**Root `Makefile` scaffolded** at the repo root — §10 automation is
done. Per-module targets `init-<name>`, `plan-<name>`, `apply-<name>`,
`destroy-<name>` where `<name>` is the short suffix (e.g. `key-vault`,
not `05-key-vault`), plus whole-estate `make apply` (01→12),
`make destroy` (12→01 with post-destroy KV purge + PG soft-delete
report), `make reprovision`, and utility targets `make fmt`,
`make validate`, `make list`, `make help`. Every recipe reuses the
same `-backend-config` + `-var-file` invocations the per-module READMEs
document, so switching between the Makefile and manual `cd + terraform`
is a no-op.

**Deviation from §12 in 09-postgresql — Option B, not Option A.** The
plan recommends `cyrilgdn/postgresql` (Option A) for the shared-UAMI
AAD-principal step. In practice, `postgresql_role` runs `CREATE ROLE`,
which in Azure Flexible Server with Entra-only auth produces a role
that CANNOT log in — only `pgaadauth_create_principal` produces
AAD-authenticated roles, and no cyrilgdn resource wraps that stored
procedure. Option B (null_resource + local-exec + psql) was chosen
instead. The script is idempotent and gated by `triggers` so re-apply
with no relevant change does not re-run. Full rationale in
`terraform/modules/postgresql/README.md` § Design decisions.

**Prereqs unique to 09-postgresql (not needed by any prior module):**

- The `pg_entra_admin_group_object_id` placeholder in
  `terraform/envs/dev/env.tfvars` must be replaced with a real Entra
  group objectId, and the Terraform SP must be a member of that group.
- The runner needs `az` (2.60+), `psql` (Postgres client 15+), and
  `bash` on `PATH`. The null_resource shells out to all three.

**Sanity check.** `make validate` was run across all 12 module roots
after the Makefile landed — every root passes `terraform validate` with
no cloud calls.

## Deferred work (project paused 2026-07-15)

Everything below is optional or blocked on non-IaC work. The estate is
fully provisioned in code and self-contained; pick any item up in
isolation when there's appetite. In rough priority order:

### D1. Wire real Java / Spring Boot images into module 11 (app work)

Blocked on the Spring Boot 4.1.x microservices being built and pushed
to `rubensdevacr`. Module 11 is currently destroyed (2026-07-26); when
it was last up it ran `mcr.microsoft.com/k8se/quickstart:latest` on port
80 as a placeholder. Because the apps are already down, wiring real
images is a fresh apply, not a replace — no need to destroy first.

When images exist:
1. In `terraform/envs/dev/11-container-apps/terraform.tfvars`, uncomment
   and set `apps_image_map` (map: app-name → full ACR image reference,
   e.g. `rubensdevacr.azurecr.io/api:1.0.0`) and `target_port` (Spring
   Boot default `8080`).
2. `make apply-container-apps`.

See `terraform/envs/dev/11-container-apps/README.md` → "Swapping the
placeholder image" for the full checklist.

### D2. Wire `APPLICATIONINSIGHTS_CONNECTION_STRING` into the Container Apps

Depends on D1 — pointless until real apps are running. Module 12 already
exports the value as the sensitive output `ai_connection_string`.

Change is in the child module: add one `env` block to the container
template in `terraform/modules/container-apps/main.tf`, sourced from a
new variable that the 11-container-apps root wires up from
`data.terraform_remote_state.monitoring.outputs.ai_connection_string`.
The Azure Monitor OpenTelemetry SDK on the Java side reads the env var
directly — no code change beyond dependency + auto-instrumentation
setup. Noted in `terraform/envs/dev/12-monitoring/README.md` → Notes →
"App Insights connection string".

### D3. §12a — PG data-plane bootstrap as a Container Apps Job

Replaces the manual `shell.azure.com` step for registering the shared
UAMI as a PG AAD principal and running per-DB grants. Runs inside the
VNet so it works from any dev machine regardless of the outbound-5432
block that forced the manual workaround today (see
`terraform/modules/postgresql/README.md` → "Data-plane bootstrap" and
the auto-memory note on WSL2 network constraints).

Sketch: new module `13-pg-bootstrap-job` (Container Apps Job resource,
one-shot, `mcr.microsoft.com/azure-cli` + a shell script that runs
`pgaadauth_create_principal` and per-DB `GRANT`s using the shared
UAMI's AAD token). Section §12a of this plan has the full design.
Nice-to-have — the manual Cloud Shell workflow works today.

### D4. APIM (deferred from day one)

Explicitly out of scope for iteration 1 per `CLAUDE.md`. When it lands,
it becomes module 14 (or 13 if D3 is skipped), fronts the Container
Apps ingress, and gets its own diagnostic setting sinking into the
shared LAW created by module 03.

## Recommended approach

### 1. Per-module Terraform roots, one state file per module

Each module gets its own root under `terraform/envs/dev/<NN-module>/`, its own
remote-state key under the existing `tfstate` container, and reads upstream
outputs via `data.terraform_remote_state`. This makes iterative apply/destroy
trivial and avoids `-target` (officially discouraged).

The numeric prefix (`01-`, `02-`, ...) encodes dependency order for both humans
and the future `Makefile`. State keys drop the number so renumbering never
breaks a backend key.

### 2. Target folder layout

```
azure-iac/
├── docs/
│   └── PROVISIONING_PLAN.md              ← the master plan (this doc, rendered for the repo)
├── terraform/
│   ├── INITIAL_SETUP.md                  (existing, unchanged)
│   ├── bootstrap-backend/                (existing, unchanged)
│   ├── modules/                          (child modules — no state)
│   │   ├── resource-groups/
│   │   ├── networking/
│   │   ├── log-analytics/
│   │   ├── managed-identities/
│   │   ├── key-vault/
│   │   ├── acr/                          ← NEW (added between KV and storage)
│   │   ├── storage/
│   │   ├── service-bus/
│   │   ├── postgresql/
│   │   ├── container-app-environment/
│   │   ├── container-apps/
│   │   └── monitoring/                   (apim/ stub stays, deferred)
│   └── envs/
│       └── dev/
│           ├── env.tfvars                (shared: env, location, prefix, tags)
│           ├── backend.hcl               (shared backend config)
│           ├── 01-resource-groups/
│           ├── 02-networking/
│           ├── 03-log-analytics/
│           ├── 04-managed-identities/
│           ├── 05-key-vault/
│           ├── 06-acr/
│           ├── 07-storage/
│           ├── 08-service-bus/
│           ├── 09-postgresql/
│           ├── 10-container-app-environment/
│           ├── 11-container-apps/
│           └── 12-monitoring/
└── Makefile                              (added last, once modules are proven)
```

### 3. Resource Group partitioning (5 RGs)

| RG                     | Contains                                               | Why here                                                        |
|------------------------|--------------------------------------------------------|-----------------------------------------------------------------|
| `rg-dev-platform`      | Managed identities, Key Vault, ACR                     | Long-lived, shared across workloads; slow to rebuild            |
| `rg-dev-network`       | VNet, subnets, NSGs, private DNS zones                 | Long-lived; delegations block teardown when children exist      |
| `rg-dev-data`          | PostgreSQL, Service Bus, Storage                       | Data lifecycle; protect from `app` churn                        |
| `rg-dev-app`           | Container App Environment, Container Apps (APIM later) | Fast-iterating; destroy freely without touching data            |
| `rg-dev-observability` | Log Analytics workspace, App Insights, Action Groups   | Referenced by many, references none — safe orthogonal lifecycle |

### 4. Module provisioning order (dependency-driven)

| #  | Module                      | Depends on (via remote_state)                                                                            | Key outputs consumed downstream                                                                                                                                                                                                                                                                                                                                  |
|----|-----------------------------|----------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 01 | `resource-groups`           | —                                                                                                        | `rg_{platform,network,data,app,observability}_{name,id,location}`                                                                                                                                                                                                                                                                                                |
| 02 | `networking`                | 01                                                                                                       | `vnet_id`, `subnet_{app,pg,pe}_id`, `dns_zone_ids`                                                                                                                                                                                                                                                                                                               |
| 03 | `log-analytics`             | 01                                                                                                       | `law_id`, `law_workspace_id`, `law_primary_shared_key`                                                                                                                                                                                                                                                                                                           |
| 04 | `managed-identities`        | 01                                                                                                       | `uami_app_{id,principal_id,client_id,name}` — **one shared UAMI (`id-dev-app`)** attached to every microservice in the ACA environment                                                                                                                                                                                                                           |
| 05 | `key-vault`                 | 01, 02, 04                                                                                               | `kv_id`, `kv_uri`, `kv_name`. Grants the shared UAMI `Key Vault Secrets User` on the vault                                                                                                                                                                                                                                                                       |
| 06 | `acr`                       | 01, 02, 04, 05                                                                                           | `acr_id`, `acr_login_server`. Grants the shared UAMI `AcrPull` on ACR (image pull is passwordless)                                                                                                                                                                                                                                                               |
| 07 | `storage`                   | 01, 02, 04, 05                                                                                           | `sa_id`, `sa_primary_blob_endpoint`, `container_names`. **Grants the shared UAMI `Storage Blob Data Contributor` at the storage account scope**. No account keys or connection strings stored anywhere — apps read blobs via `DefaultAzureCredential`                                                                                                            |
| 08 | `service-bus`               | 01, 04, 05                                                                                               | `sb_namespace_id`, `sb_queue_names`. Grants the shared UAMI `Azure Service Bus Data Sender` and `Data Receiver` at the namespace scope (passwordless — no SAS keys)                                                                                                                                                                                              |
| 09 | `postgresql`                | 01, 02, 04, 05                                                                                           | `pg_fqdn`, `pg_databases` map: `{ <app> => <db_name> }`. Provisions the flexible server with **Entra-only authentication enabled**, sets an Entra admin group for management, creates one DB per app, registers the shared UAMI once as an AAD principal in PG, and grants it `CONNECT` + schema privileges on every app DB (see §12)                            |
| 10 | `container-app-environment` | 01, 02, 03                                                                                               | `cae_id`, `cae_default_domain`, `cae_static_ip`                                                                                                                                                                                                                                                                                                                  |
| 11 | `container-apps`            | 01, 04, 06, 08, 09, 10 (Key Vault only if the estate has app-specific secrets beyond passwordless creds) | `app_fqdns`, `app_names`. Every `azurerm_container_app` attaches the **same shared UAMI**, uses ACR pull via that UAMI (`registries` block with `identity = <shared-uami-id>`), and receives env vars for `AZURE_CLIENT_ID` (of the shared UAMI), PG host, its own DB name, storage account & container names — **no passwords, no keys, no connection strings** |
| 12 | `monitoring`                | 01, 03, plus resources emitting diagnostics                                                              | `ai_connection_string`, `action_group_ids`                                                                                                                                                                                                                                                                                                                       |

Destroy order is the strict reverse: `12 → 11 → ... → 01`.

### 5. Standard per-module scaffolding

Every `envs/dev/<NN-module>/` root gets these files (mirroring
`bootstrap-backend/` conventions):

- `versions.tf` — required_version `~> 1.15`; providers pinned identically to
  bootstrap (`azurerm ~> 4.80`, `azurecaf ~> 1.2`, `azapi ~> 2.10`).
- `providers.tf` — `provider "azurerm" { features {} }`; auth via `ARM_*` env
  vars (never in code).
- `backend.tf` — **empty** `terraform { backend "azurerm" {} }` block; values
  arrive at init time.
- `main.tf` — calls the child module in `terraform/modules/<name>/` + any
  `data.terraform_remote_state` blocks.
- `variables.tf` — module-specific variables + shared shape (`env`, `location`,
  `prefix`, `tags`).
- `outputs.tf` — re-exports whatever downstream modules will consume.
- `terraform.tfvars` — module-specific values (always passed via explicit
  `-var-file`).
- `README.md` — copy-paste command sequence for that module.

### 6. Shared config files (populate before module 01)

**`terraform/envs/dev/env.tfvars`** (currently empty):

```hcl
env      = "dev"
location = "eastus"
prefix   = "rg"

# One PG database per app in this list. All apps share ONE UAMI (id-dev-app);
# adding a microservice here creates its DB and grants the shared UAMI access.
apps = ["api", "worker"]

# Entra group whose members can administer PostgreSQL (needed to create
# per-app AAD principals inside the DB). Members typically include YOU
# and the Terraform SP. Group must exist in the tenant before apply.
pg_entra_admin_group_object_id = "<REPLACE-with-Entra-group-objectId>"

tags = {
  managedBy   = "terraform"
  environment = "dev"
  owner       = "rubens"
  costCenter  = "learning"
}
```

**`terraform/envs/dev/backend.hcl`** (new):

```hcl
resource_group_name  = "rg-tfstate"
storage_account_name = "sttfstaterubens01"
container_name       = "tfstate"
use_azuread_auth     = false
```

State layout inside the `tfstate` container:

```
bootstrap/backend.tfstate                     (existing)
resource-groups/terraform.tfstate
networking/terraform.tfstate
log-analytics/terraform.tfstate
managed-identities/terraform.tfstate
key-vault/terraform.tfstate
acr/terraform.tfstate
storage/terraform.tfstate
service-bus/terraform.tfstate
postgresql/terraform.tfstate
container-app-environment/terraform.tfstate
container-apps/terraform.tfstate
monitoring/terraform.tfstate
```

### 7. Naming conventions (via `azurecaf`)

Let `azurecaf_name` compute names with `prefixes = [var.prefix, var.env]` and
`random_length = 4` for globally-unique resources (KV, SA, ACR, SB,
LA-optional).

| Resource type                  | Pattern                                 | Example              |
|--------------------------------|-----------------------------------------|----------------------|
| Resource Group                 | `rg-<env>-<purpose>`                    | `rg-dev-platform`    |
| Virtual Network                | `vnet-<env>`                            | `vnet-dev`           |
| Subnet                         | `snet-<env>-<purpose>`                  | `snet-dev-app`       |
| NSG                            | `nsg-<env>-<subnet>`                    | `nsg-dev-app`        |
| Log Analytics Workspace        | `log-<env>-<random>`                    | `log-dev-a7f2`       |
| User-Assigned Managed Identity | `id-<env>-app` (single shared identity) | `id-dev-app`         |
| Key Vault                      | `kv-<env>-<prefix>-<random>`            | `kv-dev-rubens-a7f2` |
| Azure Container Registry       | explicit, per-env (no dashes)           | `rubensdevacr`       |
| Storage Account                | `st<env><purpose><random>` (no dashes)  | `stdevappa7f2`       |
| Service Bus Namespace          | `sb-<env>-<purpose>-<random>`           | `sb-dev-msg-a7f2`    |
| PostgreSQL Flexible Server     | `psql-<env>-<random>`                   | `psql-dev-a7f2`      |
| Container App Environment      | `cae-<env>`                             | `cae-dev`            |
| Container App                  | `ca-<env>-<app>`                        | `ca-dev-api`         |
| Application Insights           | `appi-<env>`                            | `appi-dev`           |

Every resource takes `tags = var.tags` merged with optional module-local tags.

### 8. Provision / Verify / Destroy / Reprovision workflow (template)

Every module follows the same four-step shape:

```bash
# 1. Provision — init the module's state, plan against the target, apply.
cd terraform/envs/dev/<NN-module>
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=<module>/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan

# 2. Verify — module-specific `az` spot-check (see §13).

# 3. Destroy — reverse of provision. May require a purge step after (§13).
#    To tear down the WHOLE estate rather than one module, use §15.
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars

# 4. Reprovision — same commands as step 1, or the shortcut below.
```

**Reprovision after `terraform destroy` — what you can and cannot skip:**

- `terraform init` — **skip.** Destroy doesn't touch `.terraform/` or
  `.terraform.lock.hcl`, so init is unnecessary if you're in the same working
  directory on the same machine. It's idempotent, so re-running is harmless.
  You **do** need it again if you `rm -rf .terraform`, move to a fresh clone,
  or switch machines.
- `terraform plan -out=tfplan` — **do NOT skip.** The `tfplan` file on disk
  from before the destroy is now stale (see next note). You must either
  regenerate it or drop the saved-plan workflow entirely.
- `terraform apply tfplan` — **do NOT re-use the old `tfplan`.** It was pinned
  to the pre-destroy state serial; destroy bumped the serial; apply refuses to
  proceed. You'll see `Error: Saved plan is stale` if you try.

Two valid shapes for reprovision:

```bash
# Option A — regenerate the saved plan, then apply it.
cd terraform/envs/dev/<NN-module>
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan

# Option B — skip the saved-plan step; apply computes the plan inline
# and prompts yes/no before applying.
cd terraform/envs/dev/<NN-module>
terraform apply -var-file=../env.tfvars -var-file=terraform.tfvars
```

Both end in the same state. Option A matches the copy-paste blocks in §13.
Option B is shorter when you don't need the "review then commit" gate.

The remote state file in the `tfstate` container is retained across destroy
(it just records zero resources), so either option picks up where you left
off — no state migration or re-import needed.

**"Saved plan is stale" error:** Terraform's saved plan file is a snapshot
pinned to the state serial it saw at plan time. Any state change between
plan and apply — a destroy, another apply, a manual `terraform state`
command, a portal edit that a refresh picked up — invalidates it. Fix:
regenerate the plan (`terraform plan ... -out=tfplan`) and re-run
`terraform apply tfplan`, or apply inline (Option B above).

**Gotcha — resources landing in the wrong module's state:** `terraform
apply` writes to whichever backend key the *current directory* was
`init`'d against, regardless of what module code happens to live in the
`.tf` files. If you prototype a new module inside an existing module's
folder (e.g. drafting `module "storage"` inside `06-acr/` before splitting
it out to `07-storage/`) and apply once before moving the code, those
resources end up in the wrong state key (`acr/terraform.tfstate` instead
of `storage/terraform.tfstate`). Symptoms on the next plan in the host
module: (a) the plan shows the stray resources being *destroyed* because
they're "not in configuration", and (b) refresh of the stray resources
may 403 or otherwise fail if the host module's `providers.tf` lacks
provider settings the strays require (e.g. `storage_use_azuread = true`
is only set in `07-storage/providers.tf`, so refreshing a storage account
from `06-acr/` hits *"Key based authentication is not permitted on this
storage account"*). **Fix:** migrate the strays cross-backend with
`terraform state pull` → `terraform state mv -state=... -state-out=...`
→ `terraform state push`. Do NOT let the plan destroy them — the Azure
resources are real. Delete any stale `tfplan` file after migrating.

**Concrete, copy-pasteable commands for each of the 12 modules — including
the exact `-backend-config` key, the `az` verify command, and any post-destroy
purge — are in §13.**

### 9. Dev-friendly safety toggles (learning, not prod)

- **Key Vault**: `purge_protection_enabled = false`,
  `soft_delete_retention_days = 7`. **No manual purge is needed** — module 05's
  `features {}` block leaves `key_vault.purge_soft_delete_on_destroy` at its
  default of `true`, so the provider purges the vault during destroy. A blind
  `az keyvault purge` afterwards fails with `DeletedVaultNotFound`, which looks
  like breakage but means it already worked. See §15.
- **Log Analytics**: include `random_length = 4` in the name to sidestep the
  30-day soft-delete name block.
- **Storage**: `soft_delete_retention_days = 2`. **Shared-key access disabled
  ** (`shared_access_key_enabled = false`) — forces Azure AD auth for all
  data-plane access, matching the passwordless model.
- **PostgreSQL**: `backup_retention_days = 7` (min),
  `geo_redundant_backup_enabled = false`, `sku_name = "B_Standard_B1ms"`. *
  *Entra-only authentication** (
  `authentication.active_directory_auth_enabled = true`,
  `password_auth_enabled = false`) — no SQL admin password exists.
- **Service Bus**: Standard SKU. Local SAS auth stays available at the
  namespace, but the plan uses RBAC (`local_auth_enabled` can be left true for
  now; flip to `false` once every app is confirmed passwordless).

### 10. Automation (added AFTER modules are proven)

Root `Makefile` with per-module targets (`make apply-networking`,
`make destroy-key-vault`) and whole-estate targets (`make apply`,
`make destroy`, `make reprovision`) that iterate `envs/dev/[0-9][0-9]-*` in
forward order for apply and reverse for destroy. Uses the same
`-backend-config` + `-var-file` invocations. GitHub Actions reuses the same
`make` targets rather than reimplementing them — see the five workflows in
`.github/workflows/`, described in README.md and CLAUDE.md. `acr-create.yml`
is the worked example: it exports `ARM_*` and calls
`make init/plan/apply-<name>` for modules 01, 04 and 06 in order. When a
workflow and the Makefile disagree, fix the Makefile.

### 11. Documentation split

- `docs/PROVISIONING_PLAN.md` — this master plan (created).
- `terraform/envs/dev/<NN-module>/README.md` — commands live next to the code
  you `cd` into.
- `terraform/modules/<name>/README.md` — child module API (inputs, outputs,
  resources).
- Root `CLAUDE.md` — one-page pointer for future sessions: where the plan lives,
  auth model, per-module workflow.

### 12. Passwordless authentication model (single shared UAMI)

The whole estate is designed around **one shared UAMI** attached to every
microservice in the ACA environment. That single identity is the auth principal
for PG, Blob, Service Bus, KV, and ACR. No per-app RBAC, no per-app database
users beyond the shared principal — just one identity to reason about.
Playground-friendly, still fully passwordless.

The UAMI: `id-dev-app`, provisioned in `rg-dev-platform`.

**Wiring in each downstream module:**

**`managed-identities`** (module 04) — creates a **single**
`azurerm_user_assigned_identity` named `id-dev-app`. Outputs `uami_app_id`,
`uami_app_principal_id`, `uami_app_client_id`, `uami_app_name`. No `for_each`,
no map.

**`key-vault`** (module 05) — one `azurerm_role_assignment` giving the shared
UAMI `Key Vault Secrets User` at the vault scope. Apps read any shared secrets (
third-party API keys, TLS certs) via `DefaultAzureCredential`.

**`acr`** (module 06) — one `azurerm_role_assignment` giving the shared UAMI
`AcrPull` at the ACR scope. Container Apps pull images via that UAMI (
`registries { server, identity = <shared-uami-id> }`) — no admin user, no docker
credentials.

**`storage`** (module 07) — sets `shared_access_key_enabled = false` on the
storage account. One `azurerm_role_assignment` gives the shared UAMI
`Storage Blob Data Contributor` at the **storage account scope** (dev-friendly;
every app can read/write every container). If you later want isolation, tighten
to container scope in `storage/main.tf` — no downstream module cares. No account
keys or connection strings anywhere in state, KV, or app env vars.

**`service-bus`** (module 08) — one `azurerm_role_assignment` each for
`Azure Service Bus Data Sender` and `Data Receiver` at the namespace scope for
the shared UAMI. Apps connect using `sb.<namespace>.servicebus.windows.net` +
`DefaultAzureCredential` — no SAS keys.

**`postgresql`** (module 09) — passwordless PG story:

1. **Server**: `azurerm_postgresql_flexible_server` with
   `authentication { active_directory_auth_enabled = true, password_auth_enabled = false, tenant_id = <tenant> }`.
   No SQL admin login exists at all.
2. **Entra admin**:
   `azurerm_postgresql_flexible_server_active_directory_administrator` binds the
   `pg_entra_admin_group_object_id` group as the server administrator. Members
   of that group can connect to PG using their own Entra tokens.
3. **Databases**: one `azurerm_postgresql_flexible_server_database` per app in
   `var.apps` (`for_each` on the app list).
4. **AAD principal + grants inside PG**: **register the shared UAMI once** as an
   AAD-authenticated PG role (
   `SELECT pgaadauth_create_principal('id-dev-app', false, false);`), then grant
   `CONNECT` on every app DB and default schema privileges.

   **Plan of record** — the SQL is idempotent (guarded by `IF NOT EXISTS` and
   `GRANT` semantics), so the same statements can run from three different
   drivers with the same end-state. The plan iterated through all three during
   module 09's bring-up; the current choice is **C** (manual one-shot), moving
   to **D** (Container Apps Job) as a follow-on. See §12a for D.

   - **A. `cyrilgdn/postgresql` provider** — declarative, but its
     `postgresql_role` runs a plain `CREATE ROLE`, which cannot register an AAD
     principal on Flexible Server with `password_auth_enabled = false`. Rejected
     during module 09 implementation. Kept here so future work knows why.
   - **B. `null_resource` + `local-exec` running `psql`** — the child module
     still ships this path (gated behind `var.run_bootstrap`, default `false`).
     Fails outright when the runner's network blocks outbound TCP 5432, which
     is standard corporate / home ISP policy. Usable only from a self-hosted
     runner inside an Azure VNet or a network that allows outbound 5432.
   - **C. Manual one-shot from Azure Cloud Shell** (current). Cloud Shell
     egresses from Azure public IPs and is covered by the
     `allow-azure-services` firewall rule, so it bypasses runner-side egress
     blocks entirely. The exact commands live in
     `envs/dev/09-postgresql/README.md` → "Data-plane bootstrap (Cloud Shell)".
     Downside: Terraform doesn't know the step ran, so this is a documented
     operational task, not IaC.
   - **D. Container Apps Job triggered by GitHub Actions** — see §12a.

5. **Network**: the server uses `PublicNetworkAccessEnabled = true` during
   bootstrap with two firewall rules — one for the runner's public IP (fetched
   via the `http` data source), one for Azure Services (`0.0.0.0/0.0.0.0`).
   The runner rule stays useful for `az` management-plane calls even when the
   data-plane bootstrap moves to Cloud Shell / a Job. Flip to VNet-only via
   `delegated_subnet_id = snet-pg` once the estate is stable.

**`container-apps`** (module 11) — each `azurerm_container_app` gets:

- `identity { type = "UserAssigned", identity_ids = [<shared-uami-id>] }` — *
  *same UAMI on every app**
- `registries { server = <acr login_server>, identity = <shared-uami-id> }` —
  passwordless image pull
- Env vars only (no `secret {}` blocks for connection info):
    - `AZURE_CLIENT_ID` = shared UAMI `client_id` (so `DefaultAzureCredential`
      uses this identity)
    - `POSTGRES_HOST` = `<pg_fqdn>`
    - `POSTGRES_DB` = the app's own DB name (differs per app)
    - `POSTGRES_USER` = `id-dev-app` (matches the AAD principal registered in
      PG — same for every app)
    - `STORAGE_ACCOUNT_NAME`, `STORAGE_CONTAINER_NAME` (per-app if you split
      containers; otherwise SA-wide)
    - `SERVICEBUS_NAMESPACE_FQDN`
- App code uses `DefaultAzureCredential` (Azure SDK) to get tokens for PG (
  `https://ossrdbms-aad.database.windows.net`), Blob (
  `https://<sa>.blob.core.windows.net`), and Service Bus. No client secrets, no
  connection strings, no PG password parameter anywhere.

**What lives in Key Vault vs. not:**

- In KV: any third-party API keys, external SaaS credentials, TLS certs the apps
  need.
- Not in KV: PG password (doesn't exist), storage account key (disabled),
  Service Bus SAS (unused), ACR credentials (not created).

**Trade-off flagged:** any Terraform-driven PG data-plane step (options A / B
above) requires the Terraform SP to have (i) membership in the Entra admin
group and (ii) outbound TCP 5432 reachability to the server. Point (ii) is a
hard blocker in most corporate / home networks; that is why the current plan
uses option C (Cloud Shell) and treats the data-plane step as an operational
task rather than part of `terraform apply`. The Job-based option D (§12a)
lifts point (ii) by running the SQL from inside Azure.

**Trade-off of the shared-UAMI choice:** all apps share the same blast-radius on
any RBAC role. If `api` is compromised, the attacker has the same PG/Blob/SB
permissions as `worker`. Acceptable for a learning playground; document as a
known limitation to revisit if this graduates to a production-shaped project.

### 12a. PG data-plane bootstrap follow-on: Container Apps Job

**Status:** planned, not implemented. Tracked here so the design is captured
before module 10 lands.

**Motivation.** The manual Cloud Shell path (§12 option C) works but is a
person-in-the-loop step every time the app list changes. A Job-based approach
folds the same work back into a CI pipeline without needing runner-side egress
on port 5432 — the container runs inside Azure, so PG's
`allow-azure-services` firewall rule covers it and no runner IP allow-listing
is needed.

**Prerequisites** (must be in place before the Job can run):

- Module 06 (ACR) — already provisioned; holds the bootstrap image.
- Module 09 (this module) — provisioned with `run_bootstrap = false`.
- Module 10 (Container Apps Environment) — the Job runs inside the ACAE.
- The shared UAMI (`id-dev-app`) as the Job's identity, AND that UAMI already
  registered as an AAD principal in PG. **Chicken-and-egg**: the first-ever
  Job run still needs the UAMI registered by an admin group member.
  Resolution: run the Cloud Shell bootstrap ONCE at estate creation; every
  subsequent app-list change goes through the Job. Alternatively, register
  the UAMI in `pgaadauth_create_principal` via a separate one-shot Job that
  runs under an admin-group member's identity (workload identity federated
  to a human's session) — more moving parts, drop for a playground.

**Design.**

1. **Bootstrap image.** A small OCI image built + pushed to ACR (mod 06).
   Contents: `alpine` base + `postgresql-client` + `azure-cli` (or just the
   Azure Identity SDK, if the entrypoint is a script that fetches the token
   via IMDS directly). Entrypoint: the same script that today lives at
   `modules/postgresql/scripts/pg-bootstrap.sh.tftpl`, parametrised via env
   vars instead of `templatefile()`.

2. **Job resource.** `azurerm_container_app_job` in module 10 (or a new
   module 09a — TBD). Key settings:
   - `identity { type = "UserAssigned", identity_ids = [<shared-uami-id>] }` —
     same shared UAMI the apps use. Job authenticates to PG via
     `DefaultAzureCredential` inside the container.
   - `registry { server = <acr>, identity = <shared-uami-id> }` — passwordless
     image pull.
   - `trigger_type = "Manual"` — invoked by GHA, not on a schedule. (Could
     also be `"Event"` on a Service Bus queue if we later want the pipeline
     to publish an app-list change event.)
   - Environment: `PG_FQDN`, `ADMIN_GROUP`, `UAMI_NAME`, `APPS` (comma-sep).
     No secrets — token comes from IMDS at runtime.

3. **GitHub Actions workflow.** `pg-bootstrap.yml`. Trigger: `workflow_dispatch`
   + `push` on changes to `envs/dev/env.tfvars` (which is where `apps` lives).
   Steps: OIDC-federated `az login` → `az containerapp job start` → poll for
   completion → propagate exit code. Failure surfaces on the PR / workflow
   run, not in terraform.

4. **Retirement of `null_resource.pg_bootstrap`.** Once D is in place, remove
   the `null_resource` and the `run_bootstrap` variable from
   `modules/postgresql/main.tf` + `variables.tf`. The child module gets
   simpler; the data-plane step lives entirely in the Job.

**Open questions to resolve during implementation:**

- Where does the Job live — module 09a, module 10 (ACAE root), or module 11
  (container-apps root)? Leaning towards a new **module 09a** so PG data-plane
  ownership stays with PG.
- OIDC federation on the Terraform SP vs. a dedicated GHA SP? Playground can
  reuse the Terraform SP; production would split.
- Image build pipeline: same GHA workflow, or a separate `build-bootstrap.yml`
  that only fires when the `Dockerfile` or bootstrap script changes? Prefer
  separate — Job invocations shouldn't rebuild the image every time.

### 13. Per-module command reference

Every block is copy-pasteable from the **repo root**. Each module has three
sections: **Provision**, **Verify**, **Destroy**. Post-destroy purge is called
out where the resource has a soft-delete window (Key Vault, PostgreSQL).

Prerequisites — set once per shell before running any block:

```bash
export ARM_CLIENT_ID=<sp-app-id>
export ARM_CLIENT_SECRET=<sp-secret>
export ARM_TENANT_ID=<tenant-id>
export ARM_SUBSCRIPTION_ID=<subscription-id>
```

See `terraform/INITIAL_SETUP.md` for how the SP was created and what roles it
holds.

#### 13.01 resource-groups

```bash
# Provision
cd terraform/envs/dev/01-resource-groups
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=resource-groups/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify (from anywhere)
az group list \
  --query "[?starts_with(name,'rg-dev-')].{Name:name, State:properties.provisioningState}" \
  -o table
# Expect 5 rows, all Succeeded: rg-dev-{platform,network,data,app,observability}
```

```bash
# Destroy — blocked while any downstream module still holds resources here.
cd terraform/envs/dev/01-resource-groups
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
# No post-destroy purge (RGs have no soft-delete window).
```

#### 13.02 networking

```bash
# Provision
cd terraform/envs/dev/02-networking
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=networking/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
az network vnet list -g rg-dev-network -o table
az network vnet subnet list -g rg-dev-network --vnet-name vnet-dev -o table
# Expect: vnet-dev present; snet-dev-{app,pg,pe} listed.
```

```bash
# Destroy — subnet delegations can block if downstream modules still hold refs.
cd terraform/envs/dev/02-networking
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

#### 13.03 log-analytics

```bash
# Provision
cd terraform/envs/dev/03-log-analytics
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=log-analytics/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
az monitor log-analytics workspace list -g rg-dev-observability -o table
# Expect: log-dev-<random> present, provisioningState = Succeeded.
```

```bash
# Destroy — 30-day soft-delete on the name. The <random> suffix sidesteps
# the block on immediate reprovision under the same name.
cd terraform/envs/dev/03-log-analytics
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

#### 13.04 managed-identities

```bash
# Provision
cd terraform/envs/dev/04-managed-identities
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=managed-identities/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
az identity show -g rg-dev-platform -n id-dev-app \
  --query "{name:name, clientId:clientId, principalId:principalId}" -o table
```

```bash
# Destroy — RBAC assignments granting this UAMI live in downstream modules
# (05, 06, 07, 08). They must be destroyed first, or those role assignments
# will orphan.
cd terraform/envs/dev/04-managed-identities
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

#### 13.05 key-vault

```bash
# Provision
cd terraform/envs/dev/05-key-vault
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=key-vault/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
az keyvault list -g rg-dev-platform -o table
KV_NAME=$(cd terraform/envs/dev/05-key-vault && terraform output -raw kv_name)
az keyvault show -n "$KV_NAME" --query "properties.provisioningState" -o tsv
```

```bash
# Destroy. NO manual purge needed: this root's `features {}` leaves
# `key_vault.purge_soft_delete_on_destroy` at its default `true`, so the
# provider purges the soft-deleted vault itself. Purging by hand afterwards
# returns `(DeletedVaultNotFound) ... does not exist` — that means it already
# worked, not that it failed. See §15.
cd terraform/envs/dev/05-key-vault
KV_NAME=$(terraform output -raw kv_name)   # capture BEFORE destroy
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars

# Confirm it is gone (expect an empty list):
az keyvault list-deleted --query "[?name=='$KV_NAME']" -o table
```

#### 13.06 acr

```bash
# Provision
cd terraform/envs/dev/06-acr
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=acr/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
az acr list -g rg-dev-platform -o table
ACR_NAME=$(cd terraform/envs/dev/06-acr && terraform output -raw acr_name)
az acr show -n "$ACR_NAME" --query "provisioningState" -o tsv
```

```bash
# Destroy — no post-destroy purge needed (ACR has no soft-delete window
# on Basic SKU).
cd terraform/envs/dev/06-acr
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

#### 13.07 storage

```bash
# Provision
cd terraform/envs/dev/07-storage
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=storage/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
SA_NAME=$(cd terraform/envs/dev/07-storage && terraform output -raw sa_name)
az storage account show -g rg-dev-data -n "$SA_NAME" \
  --query "{name:name, provisioningState:provisioningState, sharedKey:allowSharedKeyAccess}" -o table
# Expect sharedKey = false (passwordless model).
```

```bash
# Destroy — 2-day soft-delete window (dev toggle). No purge command needed;
# the name blocks reprovision only within the 2-day window under the same name.
cd terraform/envs/dev/07-storage
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

#### 13.08 service-bus

```bash
# Provision
cd terraform/envs/dev/08-service-bus
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=service-bus/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
SB_NAME=$(cd terraform/envs/dev/08-service-bus && terraform output -raw sb_namespace_name)
az servicebus namespace show -g rg-dev-data -n "$SB_NAME" \
  --query "{name:name, status:status, sku:sku.name}" -o table
```

```bash
# Destroy — no post-destroy purge required.
cd terraform/envs/dev/08-service-bus
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

#### 13.09 postgresql

```bash
# Provision — Terraform SP must (a) reach the PG server (public access + FW
# rule during bootstrap) and (b) be a member of the Entra group whose objectId
# is pg_entra_admin_group_object_id in env.tfvars, so the cyrilgdn/postgresql
# step can obtain an AAD token and create the shared UAMI as a PG principal.
cd terraform/envs/dev/09-postgresql
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=postgresql/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
PG_NAME=$(cd terraform/envs/dev/09-postgresql && terraform output -raw pg_server_name)
az postgres flexible-server show -g rg-dev-data -n "$PG_NAME" \
  --query "{name:name, state:state, fqdn:fullyQualifiedDomainName}" -o table
az postgres flexible-server db list -g rg-dev-data -s "$PG_NAME" -o table
# Expect one DB per entry in var.apps.
```

```bash
# Destroy. Flexible Server retains the name up to 7 days, but there is NO az
# command to list dropped servers (`--show-deleted` does not exist; neither
# does `list-deleted`). It does not matter: the server is named
# `psql-<env>-<random_id>`, so a fresh apply gets a new name and never
# collides. `az postgres flexible-server revive-dropped` recovers one if needed.
#
# WARNING — this destroy commonly stalls for 30 minutes and then fails on
# every child resource at once (firewall rules, databases, Entra admin) with
# "HTTP response was nil" / "context deadline exceeded". That is the provider's
# default 30m delete timeout: Azure serializes child ops on the server, and the
# five parallel deletes queue until they all time out. Deleting the SERVER
# cascades to every child, so when you are tearing down for good, skip the
# child deletes entirely:
#
#   az postgres flexible-server delete -g rg-dev-data -n "$PG_NAME" --yes
#   terraform destroy ...   # refreshes, sees 404s, no-ops
#
# Full write-up in §15.
cd terraform/envs/dev/09-postgresql
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

#### 13.10 container-app-environment

```bash
# Provision
cd terraform/envs/dev/10-container-app-environment
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=container-app-environment/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
az containerapp env show -g rg-dev-app -n cae-dev \
  --query "{name:name, state:properties.provisioningState, defaultDomain:properties.defaultDomain}" -o table
```

```bash
# Destroy — blocked while any Container App still lives in this environment
# (module 11 must be destroyed first).
cd terraform/envs/dev/10-container-app-environment
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

#### 13.11 container-apps

```bash
# Provision
cd terraform/envs/dev/11-container-apps
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=container-apps/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
az containerapp list -g rg-dev-app -o table
# Expect one row per entry in var.apps (e.g. ca-dev-api, ca-dev-worker).
```

```bash
# Destroy — safe to run any time; apps depend on nothing downstream.
cd terraform/envs/dev/11-container-apps
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

#### 13.12 monitoring

```bash
# Provision
cd terraform/envs/dev/12-monitoring
terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=monitoring/terraform.tfstate"
terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

```bash
# Verify
az monitor app-insights component show -g rg-dev-observability -a appi-dev \
  --query "{name:name, kind:kind, state:provisioningState}" -o table
az monitor action-group list -g rg-dev-observability -o table
```

```bash
# Destroy
cd terraform/envs/dev/12-monitoring
terraform destroy -var-file=../env.tfvars -var-file=terraform.tfvars
```

> **Deferred:** APIM is intentionally out of scope for the first iteration
> (`terraform/modules/apim/` stays a stub). Add it as module 13 in the second
> iteration once the estate is stable.

### 14. Full-estate provision and destroy scripts

The blocks below concatenate every module in dependency order. They exist so
you can drive the whole estate from the repo root without hopping through §13
per module.

**Provision (01 → 12):**

```bash
# Run from repo root. Assumes ARM_* env vars are exported.
set -e
for m in \
  01-resource-groups \
  02-networking \
  03-log-analytics \
  04-managed-identities \
  05-key-vault \
  06-acr \
  07-storage \
  08-service-bus \
  09-postgresql \
  10-container-app-environment \
  11-container-apps \
  12-monitoring; do
  key="${m#[0-9][0-9]-}"
  echo "=== APPLY $m ==="
  ( cd "terraform/envs/dev/$m" \
    && terraform init -reconfigure \
         -backend-config=../backend.hcl \
         -backend-config="key=${key}/terraform.tfstate" \
    && terraform apply -auto-approve \
         -var-file=../env.tfvars -var-file=terraform.tfvars )
done
```

**Destroy (12 → 01):**

```bash
# Run from repo root. Assumes ARM_* env vars are exported, AND a separate
# `az login` session (the az CLI does not inherit ARM_*). Captures the Key
# Vault name before destroy for the post-destroy check at the bottom.
set -e

# NOTE the `terraform init` before the `terraform output`. Without it, a
# preceding `make validate` (which inits with `-backend=false`) leaves
# `.terraform/` pointing at an empty LOCAL backend, `output` fails, `|| true`
# swallows the error, and the purge below is silently skipped. See §15.
KV_NAME=$(cd terraform/envs/dev/05-key-vault 2>/dev/null \
  && terraform init -reconfigure -backend-config=../backend.hcl \
       -backend-config="key=key-vault/terraform.tfstate" >/dev/null 2>&1 \
  && terraform output -raw kv_name 2>/dev/null || true)

for m in \
  12-monitoring \
  11-container-apps \
  10-container-app-environment \
  09-postgresql \
  08-service-bus \
  07-storage \
  06-acr \
  05-key-vault \
  04-managed-identities \
  03-log-analytics \
  02-networking \
  01-resource-groups; do
  # Sweep Azure-generated orphans before module 01 tries to delete the RGs.
  # Creating an Application Insights component makes Azure ALSO create an
  # action group named "Application Insights Smart Detection" that Terraform
  # never owned; left behind, it blocks the rg-dev-observability delete. By
  # this point every Terraform-managed resource is gone, so anything left is
  # an orphan. `--ids` because the name contains SPACES (see §15).
  if [ "$m" = "01-resource-groups" ]; then
    echo "=== SWEEP Azure-generated orphans ==="
    az monitor action-group list -g rg-dev-observability --query "[].id" \
      -o tsv 2>/dev/null | while IFS= read -r id; do
        [ -n "$id" ] && az monitor action-group delete --ids "$id" || true
      done
  fi
  echo "=== DESTROY $m ==="
  ( cd "terraform/envs/dev/$m" \
    && terraform destroy -auto-approve \
         -var-file=../env.tfvars -var-file=terraform.tfvars )
done

# Post-destroy Key Vault check. Module 05's provider uses `features {}`, so
# `key_vault.purge_soft_delete_on_destroy` takes its default of TRUE and the
# PROVIDER already purged the vault during destroy. Purging unconditionally
# therefore fails with "(DeletedVaultNotFound) ... does not exist", which reads
# like a teardown failure but means the opposite. Verify, then purge only if a
# soft-deleted vault is genuinely there.
if [ -n "$KV_NAME" ]; then
  echo "=== CHECK Key Vault $KV_NAME ==="
  KV_LOC=$(az keyvault list-deleted \
    --query "[?name=='$KV_NAME'].properties.location | [0]" -o tsv 2>/dev/null)
  if [ -n "$KV_LOC" ]; then
    az keyvault purge --name "$KV_NAME" --location "$KV_LOC"
  else
    echo "  already purged by the provider — nothing to do"
  fi
fi

# There is deliberately NO PostgreSQL step here. `az postgres flexible-server
# list --show-deleted` does NOT exist (no such flag, no `list-deleted`
# subcommand) — it errors to stderr, grep gets empty stdin, and the `||` branch
# reports "name is free to reuse" regardless of reality. It is moot anyway:
# module 09 names the server `psql-<env>-<random_id>`, so a fresh apply never
# collides with a dropped server's retained name. `az postgres flexible-server
# revive-dropped` is the recovery counterpart if you ever need one back.
```

**Reprovision:** run the destroy block, then the provision block. Both are
idempotent modulo the soft-delete windows called out in §9.

Once modules 01-12 are all implemented and proven, these two blocks graduate
into a `Makefile` at repo root (see §10) with per-module and whole-estate
targets that reuse the exact same invocations.

### 15. Complete teardown — removing every provisioned resource

This is the authoritative procedure for taking the estate to zero. §14's raw
shell block still works, but `make destroy` is the supported path and is what
the steps below assume.

**Step 0 — prerequisites.**

```bash
# Terraform authenticates via the Service Principal (see INITIAL_SETUP.md).
env | grep -c ARM_          # expect 4

# The az CLI authenticates SEPARATELY. `az keyvault purge` and the
# verification commands below will NOT inherit the ARM_* variables.
az account show >/dev/null || az login
```

**Step 1 — tear the estate down.**

```bash
make destroy          # from repo root; walks 12 → 01
```

The recipe prints its pre-destroy name capture before doing anything:

```
Pre-destroy capture: KV_NAME='kv-dev-rubens-820c' PG_NAME='pg-dev-rubens'
```

If either value is empty, **stop** — the corresponding post-destroy purge or
soft-delete report will be skipped. See the failure modes at the end of this
section.

Modules that are already destroyed (e.g. 11 after a `make destroy-container-apps`)
run against an empty state and no-op. That is not an error.

**A failure stops the whole loop.** The recipe runs under `set -e`, so if
module 09 fails, modules 08 → 01 are never attempted and their resources are
left untouched. Read the last `=== DESTROY <module> ===` banner to see how far
it got, fix that module (see the failure modes below), then simply re-run
`make destroy` — already-destroyed modules no-op, so the loop is resumable and
safe to run repeatedly.

**Step 2 — verify nothing survived.**

```bash
az group list -o table            # only rg-tfstate + NetworkWatcherRG remain
az keyvault list-deleted -o table # empty — see the Key Vault note below
az resource list --query "[?starts_with(resourceGroup, 'rg-dev')]" -o table
```

**Key Vault needs no manual purge.** Module 05's provider block is `features {}`,
so `key_vault.purge_soft_delete_on_destroy` takes its default of **`true`** and
the provider purges the vault as part of destroy. `az keyvault list-deleted`
comes back empty and `az keyvault show` reports not-found. Running
`az keyvault purge` unconditionally fails with
`(DeletedVaultNotFound) ... does not exist` — which reads like a teardown
failure but actually means the teardown worked. The Makefile therefore
*verifies* and purges only if a soft-deleted vault is genuinely present.

**There is no way to list dropped PostgreSQL servers.** `az postgres
flexible-server list --show-deleted` does not exist — no such flag, and no
`list-deleted` subcommand (az CLI 2.88.0). It previously appeared in this doc
and in the Makefile, where it failed silently: az errored to stderr, `grep` got
empty stdin, and the `||` branch printed `(none — name is free to reuse)`
whatever the truth was. It is also unnecessary — module 09 names the server
`psql-<env>-<random_id>`, so a fresh apply never collides with a dropped
server's retained name. The recovery counterpart, if you ever need a dropped
server back, is `az postgres flexible-server revive-dropped`.

**Region caveat:** module 09 pins `location = "eastus2"` in its own
`terraform.tfvars`, overriding the `eastus` in `env.tfvars`. That is deliberate,
not drift. Any teardown check scoped by region needs `--location eastus2` for
PostgreSQL while everything else is `eastus`.

**What legitimately survives, and why.** None of these are leaks:

| Survivor | Why |
|---|---|
| `rg-tfstate` + `sttfstaterubens01` + `tfstate` container | The state backend. Not managed by modules 01-12 — see the optional step below. |
| `NetworkWatcherRG` | Auto-created by Azure per-region, not by this repo. |
| `ME_cae-dev_rg-dev-app_eastus` | Azure-managed infra RG for the Container App Environment. Removed automatically when module 10 destroys the CAE — never delete it by hand. |
| Service Principal, PG Entra admin group | Created manually per `INITIAL_SETUP.md`. Delete by hand if you want a truly clean tenant. |
| PostgreSQL server name (up to 7 days) | Flexible Server has no purge command. Blocks reprovisioning under the same name; not a billable resource. |

**Optional — destroying the state backend too.**

`make destroy` never touches `terraform/bootstrap-backend/`. Removing it needs
the chicken-and-egg dance documented in that module's `backend.tf`, because you
cannot destroy the Storage Account while your state lives inside it:

```bash
cd terraform/bootstrap-backend
# 1. Comment out the `terraform { backend "azurerm" {} }` block in backend.tf.
# 2. Pull state down to a local file:
terraform init -migrate-state
# 3. Now safe to destroy:
terraform destroy
```

`enable_rg_lock = false` in its `terraform.tfvars`, so there is no
`CanNotDelete` lock to remove first. This is a one-way door — re-bootstrapping
later starts from empty state, and every module must be re-applied from scratch.

**Teardown failure modes.** All four were hit in practice during the first full
teardown. The Makefile now handles the first, third and fourth automatically;
the second is Azure/provider behaviour you work around, not a repo bug:

- **`/bin/sh: tac: command not found` — silent no-op destroy.** `tac` is GNU
  coreutils and does not exist on macOS/BSD. The destroy loop used to build its
  module list with `... | tr ' ' '\n' | tac`; on macOS the substitution returned
  empty, the loop iterated **zero times**, and the recipe went straight to the
  Key Vault purge having destroyed nothing. `set -e` cannot catch this — the
  failure is inside a command substitution used as a `for` word-list, so the
  loop's own exit status is 0. The symptom is a confusing
  `(DeletedVaultNotFound) The specified deleted vault ... does not exist`,
  which really means *the vault was never deleted*. The Makefile now reverses
  `DIRS` in pure Make (`$(call reverse,...)`) with no external tool dependency,
  and aborts if the reversed list is empty.

- **Module 09 stalls ~30 minutes, then fails on every PG child resource.**
  Symptom is a cluster of errors on the firewall rules, the databases and the
  Entra administrator, all at once:

  ```
  module.postgresql.azurerm_postgresql_flexible_server_firewall_rule.azure_services:
    Still destroying... [29m54s elapsed]
  Error: deleting "Firewall Rule (...)": performing Delete: ...
    HTTP response was nil; connection may have been reset
  Error: deleting Administrator (...): polling after
    AdministratorsMicrosoftEntraDelete: context deadline exceeded
  ```

  `29m54s` is the azurerm provider's **default 30-minute delete timeout** — the
  PG module declares no `timeouts` blocks, so defaults apply.
  `HTTP response was nil; connection may have been reset` is not a network
  fault: it is what the provider reports when the context deadline kills an
  in-flight request. `context deadline exceeded` is the same failure, less
  disguised.

  Cause: each child (2 firewall rules, 2 databases, the Entra admin) is a
  **control-plane operation on the server**, and Azure serializes them.
  Terraform fires all five in parallel, they queue behind one another, and they
  hit the 30-minute ceiling together. The server itself is usually healthy
  (`state: Ready`) — nothing is wedged.

  Fix: Terraform is doing work that need not be done at all. **Deleting the
  flexible server cascades to all of its children.** Terraform only deletes
  them individually because its dependency graph says to. When the goal is
  total removal, delete the server directly and let Terraform reconcile:

  ```bash
  az postgres flexible-server delete -g rg-dev-data -n <pg-server-name> --yes
  make destroy      # 09 refreshes, sees 404s, no-ops; loop continues 08 → 01
  ```

  Nothing blocks this — the server carries `ignore_changes = [zone]` only, no
  `prevent_destroy`. A plain retry is worth one attempt if the queued
  operations have since drained, but it re-serializes the same five deletes
  against the same ceiling. The durable repo-level fix would be `timeouts`
  blocks on the PG children; the cascade makes them largely redundant.

- **Silently skipped Key Vault check.** The `KV_NAME` capture runs before the
  destroy loop. If the last `terraform init` in `05-key-vault` was
  `make validate`'s `-backend=false` form, `.terraform/` points at an empty
  local backend, `terraform output` fails, `|| true` swallows it, and the check
  is skipped. The capture now re-inits against the real backend first and
  echoes what it found.

- **Module 01 fails: "the Resource Group still contains Resources".** The named
  resource is an action group Azure generated, not Terraform:

  ```
  Error: deleting Resource Group "rg-dev-observability": the Resource Group
  still contains Resources.
   * .../microsoft.insights/actiongroups/Application Insights Smart Detection
  ```

  Creating an Application Insights component makes Azure **also** create an
  action group named `Application Insights Smart Detection` in the same RG.
  Terraform never managed it, so module 12's destroy leaves it behind, and
  azurerm's `prevent_deletion_if_contains_resources` (default `true`) then
  refuses to delete the RG. **This recurs on every teardown** — it is not a
  one-off. `make destroy` now sweeps it automatically just before module 01;
  `make purge-orphans` runs the sweep on its own.

  To clear it by hand, delete by **resource ID**:

  ```bash
  az monitor action-group delete --ids "$(az monitor action-group list \
    -g rg-dev-observability --query "[0].id" -o tsv)"
  ```

  Do **not** use `-g <rg> -n "Application Insights Smart Detection"` — the name
  contains spaces, az parses the words as separate positional arguments, and it
  dies with `unrecognized arguments`. The failure goes to stderr with a
  non-zero exit, so if you do not check, it looks like it worked and the next
  `make destroy` fails identically.

  Resist the provider's suggested `prevent_deletion_if_contains_resources =
  false`. That disables the guard for every resource group in the root,
  permanently, to work around one known piece of Azure-generated litter.

Tell these apart by checking `.terraform/terraform.tfstate` — that marker file
is present only when the directory is init'd against the azurerm backend:

```bash
for d in terraform/envs/dev/*/; do
  printf "%-50s %s\n" "$d" "$(ls "$d.terraform/" 2>/dev/null | tr '\n' ' ')"
done
```

### 16. Release and versioning

Every release of this repo is a `MAJOR.MINOR.PATCH` git tag on `main`. The
full policy and the step-by-step procedure live in **`RELEASING.md`** at the
repo root; this section records the design so the plan stays the single place
that explains *why*.

`main` is protected and PR-only, so a release is two phases: a *release PR*
carrying the `VERSION` bump and the changelog roll, then a tag placed on `main`
after that PR merges. The tag must come second — squash-merge rewrites the
commit SHA, so a tag created before the merge would point at a commit that
never lands on `main`.

**Source of truth.** The repo-root `VERSION` file holds a bare
`MAJOR.MINOR.PATCH` (no `v`). Everything else derives from it:

| Artifact | Derivation |
| --- | --- |
| Git tag | `v$(cat VERSION)`, annotated, on the release commit |
| `CHANGELOG.md` heading | `## [$(cat VERSION)] - <date>` |
| `release` resource tag | `trimspace(file(".../VERSION"))` in every module root |
| GitHub Release | Published by `.github/workflows/release.yml` on the tag push |

**Semver semantics are infra-impact based**, not API-shaped. The governing
question is what `terraform plan` does to an already-applied estate:

- **MAJOR** — destroys or recreates an existing resource, renames one (in
  Azure the name *is* the identity), removes a module, changes the RG
  partitioning of §3, or breaks an output another module reads through remote
  state. Anything that a plain `make apply` cannot roll forward through
  unattended.
- **MINOR** — new modules or resources, new variables with safe defaults, new
  automation, provider *minor* bumps. The plan is additive or in-place.
- **PATCH** — in-place attribute tweaks, docs, `fmt`, CI fixes. No churn.

While the project is at `0.x` — i.e. while the Deferred work above is
outstanding — MINOR absorbs breaking changes. `1.0.0` is cut when a full
`make apply` from zero brings up all twelve modules with real application
images and verifies clean (D1 and D2 closed).

**Trigger is manual and explicit.** `make release-prep-patch|minor|major` picks the
level; nothing is inferred from commit messages, because the commit history
here is intentionally informal and would make an inferred bump untrustworthy.
The bump targets write `VERSION`, roll `[Unreleased]` into a dated version
section, commit, and create the annotated tag — all **locally**. `make
release-push` is a separate, deliberate step; it is the only release target
that touches the network, and the only one that is not undoable.

**Why `VERSION` is read from disk by Terraform rather than passed as `-var`.**
Each module root carries a `locals.tf` with:

```hcl
locals {
  release = trimspace(file("${path.root}/../../../../VERSION"))
}
```

and merges `release = local.release` into the shared tag map from §6/§7. A
`-var` would have worked through the Makefile and CI, but would have been
silently absent from a bare `terraform apply` typed in a module directory —
which §8 and §13 both document as a supported workflow — quietly mislabelling
the estate. Reading the file makes the stamp invocation-independent.

Two consequences follow, and both are intended:

1. Bumping `VERSION` immediately puts the estate "behind": `terraform plan`
   shows a pending `~ tags` update on every resource in all twelve modules
   until the next apply. That diff *is* the drift signal — code at the new
   release, Azure still labelled with the old one. Tag changes are in-place
   updates in `azurerm`; nothing is recreated by a version bump.
2. The stamp records the *release*, not the commit. Applying uncommitted
   work-in-progress labels resources with the last released number. Cut the
   release first, then apply.

Query it with `az group show -n rg-dev-app --query tags`.

**CI holds no Azure credentials.** `.github/workflows/release.yml` fires on
`v*.*.*`, checks that the tag, `VERSION`, and `CHANGELOG.md` agree, runs
`terraform fmt -check -recursive terraform/` and `make validate` (which inits
with `-backend=false`), runs the SonarCloud quality gate, and publishes a
GitHub Release whose body is that version's changelog section. It is not bound
to the `AZURE` environment, so pushing a release tag can never mutate the
estate — applying remains a deliberate `make apply` from a workstation, per §14.

Its one secret is `SONAR_TOKEN`, an organization Actions secret that reaches
sonarcloud.io and nothing else. The no-Azure-credentials property is unchanged.

**Static analysis gates the release.** Scanner configuration lives in
`sonar-project.properties` at the repo root and is read unmodified by both
`release.yml` and `make sonar`, so CI and a local pre-tag check cannot drift.
`sonar.qualitygate.wait=true` in that file is what makes the step blocking — the
scanner polls the gate and exits non-zero when it fails. Two consequences worth
recording:

- The gate runs *after* the tag is pushed. A red gate therefore leaves a tag
  with no GitHub Release; per §16 a published tag is never moved, so the
  remedy is the next patch release. `make sonar` before tagging avoids it —
  as does `pr-verify.yml`, which runs the same gate in PR mode on the way in,
  so by tag time a red gate should mean something changed since the merge.
- The branch name is passed per caller, not pinned in
  `sonar-project.properties`: `release.yml` sends
  `-Dsonar.branch.name=main`, `pr-verify.yml` sends nothing and lets the
  action detect the PR. Pinning it globally would make every PR analysis
  overwrite main's.
- `sonar.exclusions` must keep covering `**/.terraform/**`. `make validate`
  runs first and leaves a `.terraform/modules/` copy of every local module's
  `.tf` files; without the exclusion `sonar.sources=.` indexes both copies.

**Terraform CLI pin in CI.** All six workflows in `.github/workflows/`
(`pr-verify.yml`, `release.yml`, `acr-create.yml`, `acr-destroy.yml`,
`tf-bootstrap-create.yml`, `tf-bootstrap-destroy.yml`) pin
`terraform_version: "1.15.8"`, which is the minimum needed to satisfy the
`required_version = "~> 1.15"` declared in every `versions.tf` in the repo —
roots, child modules, and `bootstrap-backend/`. The two bootstrap workflows
originally pinned `1.14.3`, which does *not* satisfy that constraint; they
would have failed `terraform init`. Bump all six together. They also all set
`terraform_wrapper: false`, because the wrapper intercepts stdout and would
break `terraform output -raw`.

## Critical files to be created (in execution phases)

**Phase 0 — scaffolding (do once, before module 01):**

- `docs/PROVISIONING_PLAN.md` — render this plan into the repo.
- `terraform/envs/dev/env.tfvars` — populate shared vars.
- `terraform/envs/dev/backend.hcl` — new file, shared backend config.
- `CLAUDE.md` at repo root — session pointer for future work.
- `terraform/modules/acr/` — add the missing module directory.

**Phase 1..12 — per module, in order:**

- `terraform/modules/<name>/{main,variables,outputs,versions}.tf` + `README.md`
-
`terraform/envs/dev/<NN-name>/{main,providers,backend,variables,outputs,versions}.tf` +
`terraform.tfvars` + `README.md`

**Phase 13 — automation:**

- `Makefile` at repo root.

## Existing patterns to reuse

- `terraform/bootstrap-backend/versions.tf` — source of truth for provider
  version pins; copy verbatim into every module.
- `terraform/bootstrap-backend/backend.tf` — pattern for empty backend block +
  `-backend-config` init flags. Shift from static values to partial config.
- `terraform/bootstrap-backend/main.tf` — canonical
  `provider "azurerm" { features {} }`, `azurecaf_name` usage, tag map pattern.
- `terraform/bootstrap-backend/README.md` — high-quality README template (lock
  file, chicken-and-egg workflow, error recovery). Model per-module READMEs on
  this.
- `terraform/INITIAL_SETUP.md` — auth model (SP + `ARM_*` env vars) and provider
  registration prerequisites; every module inherits these.

## Verification (end-to-end)

**Per module (during iteration):**

1. `terraform apply` returns cleanly.
2. Module-specific `az` CLI command returns `Succeeded` (see per-module README
   table in the master plan doc).
3. `terraform destroy` returns cleanly; post-destroy purge (KV) succeeds; the RG
   list for the module's RG shows no orphans.
4. `terraform apply` again succeeds without manual intervention (proves
   reprovisionability).

**Full-estate (after automation lands):**

1. `make apply` walks modules 01→12, all succeed.
2. `make destroy` walks 12→01, all succeed, no orphans left (
   `az resource list -g rg-dev-*`). Confirm the run printed a non-empty
   `Pre-destroy capture:` line and actually emitted a `=== DESTROY ... ===`
   banner per module — a run that jumps straight to the purge destroyed
   nothing (§15).
3. `make reprovision` (destroy then apply) succeeds without manual intervention.
4. Existing bootstrap state remains untouched (`bootstrap/backend.tfstate` still
   present in container).

Full teardown to zero — including what legitimately survives and how to remove
the state backend itself — is §15.

## Open items (safe defaults chosen — flag if you disagree)

- **Log Analytics name**: random suffix baked in (sidesteps 30-day soft-delete
  name block). Say the word if you'd rather have a fixed name and accept the
  recover-or-wait ceremony.
- **Key Vault dev policy**: `purge_protection = false`, 7-day soft delete. The
  provider auto-purges on destroy (`purge_soft_delete_on_destroy` defaults to
  `true` under `features {}`), so no manual purge step is required. Say the
  word if you want prod-style defaults instead.
- **PostgreSQL AAD-principal bootstrap**: using `cyrilgdn/postgresql` provider (
  declarative). If you'd rather keep PG module strictly `azurerm`-only, we'll
  fall back to a `null_resource + az account get-access-token + psql` step (
  works but re-runs on every apply unless triggered carefully).
- **Entra admin group for PG**: `pg_entra_admin_group_object_id` must be set in
  `env.tfvars` before module 09 applies. If no group exists yet, we can either (
  a) create it via `azuread_group` inside the `managed-identities` module, or (
  b) you create it once in the portal and hand back the object ID. Recommend (b)
  so identity governance stays outside Terraform.
- **Storage RBAC scope**: `Storage Blob Data Contributor` at the *
  *storage-account scope** for the shared UAMI (dev-friendly, one assignment).
  Say the word if you'd rather scope per container instead.
- **Initial `var.apps` list**: plan uses `["api", "worker"]` as a placeholder —
  this list drives one PG database per name (and, later, one Container App per
  name). Confirm actual microservice names before module 09 applies; removing a
  name will destroy its DB.
