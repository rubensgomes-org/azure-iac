# PROVISION_ACR.md

Standalone runbook for bringing up **just** the Azure Container Registry —
and tearing it back down — without provisioning the rest of the estate.

Use this when you need a registry to push a project container image into and
nothing else. For the full estate, `docs/PROVISIONING_PLAN.md` is the
authoritative document; this file is a narrow slice of it.

Everything below assumes `ENV=dev` (the Makefile default).

---

## 1. What this provisions

Three modules, and only one of them costs anything:

| Module | Short name (Make) | Resource | Cost |
| --- | --- | --- | --- |
| `01-resource-groups` | `resource-groups` | 5 lifecycle RGs, incl. `rg-dev-platform` | **$0.00** |
| `04-managed-identities` | `managed-identities` | `id-dev-app` — User-Assigned Managed Identity | **$0.00** |
| `06-acr` | `acr` | `rubensdevacr` — Container Registry, Basic SKU | **~$5.07/mo** |
| `06-acr` | `acr` | `AcrPull` role assignment (UAMI → registry) | **$0.00** |

The UAMI and the registry both land in `rg-dev-platform`. Module 01 is
included in the provision sequence (§4) so it runs from any starting state;
it is a no-op when the RGs already exist.

### The registry name is fixed and explicit

The dev registry is **`rubensdevacr`**, login server
**`rubensdevacr.azurecr.io`**. It is set in exactly one place:

```hcl
# terraform/envs/dev/06-acr/terraform.tfvars
acr_name = "rubensdevacr"
```

That flows to `var.acr_name` on `modules/acr`, which uses it verbatim:
`name = var.acr_name`.

This deliberately breaks with the `<random>`-suffixed convention used by
`kv-`, `st-`, `sb-`, `log-`, and `psql-` elsewhere in the estate. The registry
name is the one name humans and CI type constantly — it appears in every image
tag, every `docker push`, every `az acr` call, and every `apps_image_map`
entry. A random suffix made it unmemorable and, worse, made it **change on
destroy+recreate**, silently invalidating every hardcoded reference.

Because the name is fixed, it is safe to hardcode and it survives a
destroy+recreate (§7).

**Constraints**, enforced by validation on `var.acr_name`:

- 5-50 characters, **alphanumeric only** — no dashes, no underscores
- **globally unique across every Azure tenant**, not just your subscription

There is no random suffix to fall back on, so an unavailable name fails the
apply outright rather than quietly landing on something else. Before setting a
name for a new environment:

```bash
az acr check-name -n <name>
# => { "nameAvailable": true, "reason": null, "message": null }
```

---

## 2. Why managed-identities must be provisioned too

This is not optional, for two independent reasons.

### Reason 1 — it is a hard dependency, and Make will not resolve it for you

`terraform/envs/dev/06-acr/main.tf` reads two upstream remote states:

```hcl
data "terraform_remote_state" "resource_groups"     { ... key = "resource-groups/terraform.tfstate" }
data "terraform_remote_state" "managed_identities"  { ... key = "managed-identities/terraform.tfstate" }
```

It consumes `rg_platform_name` from the first and `uami_app_principal_id`
from the second. If module 04 has not been applied, its state key is an empty
shell with no outputs, and **both `make plan-acr` and `make apply-acr` fail**
at plan time with:

```
Error: Unsupported attribute
  This object does not have an attribute named "uami_app_principal_id".
```

Critically, **the Makefile's per-module targets do no dependency
resolution.** The target factory declares exactly one prerequisite:

```makefile
apply-$(2): init-$(2)      # init only — never an upstream module
```

This is deliberate (see the design notes in the Makefile header): ordering
lives only in the whole-estate `apply` / `destroy` loops, so that behaviour
under `make -jN` stays strictly serial. Running `make apply-acr` by itself
will **not** quietly bring up module 04 first. You sequence it yourself.

### Reason 2 — it is the whole point of the passwordless design

`terraform/modules/acr/main.tf` sets `admin_enabled = false`. That is
deliberate and load-bearing: the admin flag mints a username/password pair for
the registry, which is exactly the credential this estate exists to avoid.

With no admin user, something still has to be allowed to pull images. That is
the shared UAMI, granted `AcrPull` at registry scope:

```hcl
resource "azurerm_role_assignment" "uami_acrpull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = var.uami_principal_id
  principal_type       = "ServicePrincipal"
}
```

Every Container App (module 11) later pulls via
`registries { server, identity = <uami-id> }` — no docker credentials
anywhere. The same identity is reused for Key Vault, Blob, Service Bus, and
PostgreSQL access (`docs/PROVISIONING_PLAN.md` §12), so provisioning it now is
work you would do anyway.

Note the UAMI gets **`AcrPull` only, never `AcrPush`** — that is intentional.
Push comes from your own `az login` (§6). Granting push to the runtime
identity would let a compromised app overwrite images.

Since a UAMI is free and takes seconds to create, decoupling ACR from it is
not worth a code change.

---

## 3. Prerequisites

- **`01-resource-groups`** — no action needed here; §4 provisions it as its
  first step and the apply is a no-op if the RGs already exist. To check ahead
  of time: `az group show -n rg-dev-platform`.
- **`ARM_*` exported in the current shell** — `ARM_CLIENT_ID`,
  `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`. Every Make
  target shells out to `terraform`, which reads these from the environment.
  See `terraform/INITIAL_SETUP.md`.
- **`az login`** as yourself, for the verification steps and for pushing
  images. This is a *different* identity from the Terraform service
  principal.

---

## 4. Provision

Run all three modules in this order. Do not skip the plan steps.

```bash
# ---- Module 01 — the resource groups ---------------------------------------
make init-resource-groups        # init backend at resource-groups/terraform.tfstate
make plan-resource-groups        # expect "No changes" if already applied, else 5 to add
make apply-resource-groups       # creates/confirms the 5 RGs incl. rg-dev-platform

# ---- Module 04 — the shared UAMI -------------------------------------------
make init-managed-identities     # init backend at managed-identities/terraform.tfstate
make plan-managed-identities     # review: expect 1 resource to add
make apply-managed-identities    # creates id-dev-app in rg-dev-platform

# ---- Module 06 — the registry ----------------------------------------------
make init-acr                    # init backend at acr/terraform.tfstate
make plan-acr                    # review: expect 2 to add (ACR, role assignment)
make apply-acr                   # creates rubensdevacr + AcrPull grant
```

### Why module 01 is in the list

Module 01 is normally already applied, and running it again is a **safe
no-op** — `terraform apply` is idempotent, and empty resource groups are free.
Including it here means the sequence works from *any* starting state without
you first having to check what is standing. `make plan-resource-groups` tells
you which case you are in: `No changes` means the RGs are already correct.

Both downstream modules read `rg_platform_name` from module 01's remote state,
so if the RGs are missing, module 04 fails at plan time with *Unsupported
attribute* — the same failure mode described in §2, one level further up the
chain.

One caveat, since `apply-` carries `-auto-approve`: if `plan-resource-groups`
shows anything other than `No changes` or a clean 5-resource create, stop and
read it. A `~ tags` update is the harmless `VERSION` drift signal (§9). A
`-/+ destroy and then create` means `env` or `location` in `env.tfvars` has
changed, which renames the RGs — do not auto-approve that.

### Ordering rule

Each `plan-` step **must** come after the previous module has actually been
*applied*, not merely planned — a root reads its upstream's committed state,
never its plan.

### What each target does

`init-`, `plan-`, `apply-`, and `destroy-` targets are generated for every
module by a factory in the Makefile. For `acr` they expand to:

| Target | Expands to (inside `terraform/envs/dev/06-acr/`) |
| --- | --- |
| `make init-acr` | `terraform init -reconfigure -backend-config=../backend.hcl -backend-config="key=acr/terraform.tfstate"` |
| `make plan-acr` | `init-acr`, then `terraform plan -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan` |
| `make apply-acr` | `init-acr`, then `terraform apply -auto-approve -var-file=../env.tfvars -var-file=terraform.tfvars` |
| `make plan-destroy-acr` | `init-acr`, then `terraform plan -destroy -var-file=../env.tfvars -var-file=terraform.tfvars -out=tfplan` |
| `make destroy-acr` | `init-acr`, then `terraform destroy -auto-approve -var-file=../env.tfvars -var-file=terraform.tfvars` |

Substitute `resource-groups` or `managed-identities` for `acr` to get the
other two modules' targets — the backend key and directory change to match,
everything else is identical. There is **no bare `make init`** target; init is
always per-module.

Notes on the mechanics:

- `plan-` and `apply-` both depend on `init-`, so running `init-` separately
  is optional. It is listed above because running it explicitly makes a
  backend-config failure obvious before you are staring at a plan.
- `-reconfigure` runs on *every* invocation. It is cheap (provider plugins are
  cached) and it repairs the `.terraform/` directory after a `make validate`,
  which inits with `-backend=false` and otherwise leaves `terraform output`
  returning nothing.
- Both var-files are always passed. `../env.tfvars` is shared across the env;
  the module's own `terraform.tfvars` is loaded second and wins on conflict.
  For modules 01 and 04 that file is empty (scaffolding consistency only);
  for module 06 it carries `acr_name = "rubensdevacr"` (§1).

### Running the same sequence in CI

`.github/workflows/provision-acr.yml` is the CI equivalent of this section. It
runs the identical `make init/plan/apply` targets for modules 01, 04, and 06
in the same order — it reimplements nothing, it just exports `ARM_*` from
GitHub secrets and calls the Makefile.

Run it standalone from the **Actions** tab (`workflow_dispatch`), or call it
from an application repository and gate the image push on its outputs:

```yaml
jobs:
  provision-acr:
    uses: rubensgomes-org/azure-iac/.github/workflows/provision-acr.yml@main
    with:
      environment_name: dev
    secrets:
      AZURE_CLIENT_ID:       ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_CLIENT_SECRET:   ${{ secrets.AZURE_CLIENT_SECRET }}
      AZURE_TENANT_ID:       ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

  push-image:
    needs: provision-acr
    runs-on: ubuntu-latest
    steps:
      - run: az acr login --name "${{ needs.provision-acr.outputs.acr_name }}"
      - run: docker push "${{ needs.provision-acr.outputs.acr_login_server }}/api:${{ github.sha }}"
```

Consuming `acr_login_server` as an output is the point — it means the
application repo never hardcodes `rubensdevacr.azurecr.io`, so a rename in
`terraform.tfvars` propagates instead of breaking `docker push` with a stale
hostname.

Three caveats specific to the CI path:

- **The `plan-*` steps gate nothing.** Same reason as the local flow (§9):
  `apply-<name>` re-plans internally under `-auto-approve` and never reads the
  saved `tfplan`. In CI there is no human between plan and apply at all, so a
  clean-looking plan step in the log is not a promise about the apply below
  it.
- **Concurrency does not span repositories.** The workflow's `concurrency`
  group is evaluated in whichever repo owns the run, so a caller's run will
  not serialise against a `workflow_dispatch` run started here. The azurerm
  backend's blob lease is the real guard: a genuine collision fails the second
  run with a state-lock error rather than corrupting anything. That is the
  intended failure mode — never work around it with `-lock=false`.
- **It runs as the `terraform-sp` Service Principal**, the same one your local
  `ARM_*` uses. It has subscription-wide write access, which is why callers
  pass the four secrets explicitly rather than `secrets: inherit`.

---

## 5. Verify

```bash
cd terraform/envs/dev/06-acr

# Confirm the name matches what terraform.tfvars asked for
terraform output -raw acr_name             # => rubensdevacr
terraform output -raw acr_login_server     # => rubensdevacr.azurecr.io

# Posture: expect sku=Basic, adminEnabled=False, publicNet=Enabled
az acr show -n rubensdevacr \
  --query "{name:name, sku:sku.name, adminEnabled:adminUserEnabled, publicNet:publicNetworkAccess, loginServer:loginServer}" \
  -o table

# The AcrPull grant landed on the shared UAMI — expect exactly one row
UAMI_PRINCIPAL=$(cd ../04-managed-identities && terraform output -raw uami_app_principal_id)
az role assignment list \
  --scope "$(terraform output -raw acr_id)" \
  --assignee "$UAMI_PRINCIPAL" \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

`adminEnabled = False` is the check that matters — if it is ever `True`, the
passwordless model has been broken.

> **Gotcha:** if `terraform output` returns nothing, the directory was last
> init'd by `make validate` (which uses `-backend=false`). Re-run
> `make init-acr`. The tell is whether `.terraform/terraform.tfstate` exists —
> it is present only when init'd against the real azurerm backend.

---

## 6. Push an image

Repositories are **not** Terraform resources. A repository springs into
existence on first push and disappears when its last image is deleted.

Because `admin_enabled = false`, you authenticate with your own Entra
identity, not docker credentials:

```bash
az acr login --name rubensdevacr

docker tag myapp:1.0 rubensdevacr.azurecr.io/myapp:1.0
docker push rubensdevacr.azurecr.io/myapp:1.0

az acr repository list -n rubensdevacr -o table
```

`az acr login` requires `AcrPush`, `Contributor`, or `Owner` on the registry —
your subscription owner account has this. The shared UAMI does not, by design.

---

## 7. Destroy

```bash
make destroy-acr                  # registry + AcrPull grant
make destroy-managed-identities   # optional — the UAMI. Reverse numeric order.
```

`make destroy-acr` alone stops all billing; the UAMI is free, so leaving it in
place costs nothing and saves a step next time.

From CI, the equivalent is the **ACR Destroy (manual)** workflow
(`.github/workflows/destroy-acr.yml`), run from the Actions tab. It destroys
module 06 only — resource groups and the managed identity are left standing,
and a guard step aborts the run if the destroy plan says otherwise. It asks you
to type `DESTROY ACR rubensdevacr` before it will proceed.

No post-destroy purge is needed. Basic-SKU ACR has no soft-delete concept, so
the name is released immediately — unlike Key Vault, which needs the purge
handling documented in `docs/PROVISIONING_PLAN.md` §15.

### Read this before destroying

- **Every image in the registry is deleted, permanently.** There is no
  recycle bin on Basic SKU. Push anything you care about somewhere else
  first.
- **The name survives, the images do not.** `acr_name` is a fixed input, not
  generated state, so `make apply-acr` brings the registry back as
  `rubensdevacr` with the same login server. Basic SKU has no soft-delete, so
  the name is released on destroy and immediately reusable. Dockerfiles, CI
  pipelines, and `apps_image_map` entries referencing
  `rubensdevacr.azurecr.io` stay valid — you only need to re-push the images.
- **Destroy module 11 first if Container Apps are running.** They hold image
  references into this registry. Tear down `make destroy-container-apps`
  before `make destroy-acr`, or you break running apps.
- **`destroy-` is `-auto-approve`.** There is no confirmation prompt. The
  deletion begins the moment you press enter.

To preview a teardown without doing it:

```bash
cd terraform/envs/dev/06-acr && terraform plan -destroy \
  -var-file=../env.tfvars -var-file=terraform.tfvars
```

---

## 8. Cost

Figures pulled from the Azure retail pricing API for `eastus` (the region set
in `terraform/envs/dev/env.tfvars`). Verify current numbers with:

```bash
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20'Container%20Registry'%20and%20armRegionName%20eq%20'eastus'"
```

### An empty registry costs exactly the same as a full one

ACR bills a flat **per-registry-per-day** charge — the "Registry Unit" meter.
It starts the moment the registry exists and runs until it is deleted. There
is no free tier, no scale-to-zero, and no per-repository or per-image
component. Creating a registry and never pushing to it costs full price.

| SKU | Registry unit | Per month | Per year | Included storage |
| --- | --- | --- | --- | --- |
| **Basic** (this project) | $0.1666/day | **$5.07** | $60.81 | 10 GiB |
| Standard | $0.6666/day | $20.28 | $243.31 | 100 GiB |
| Premium | $1.6666/day | $50.69 | $608.31 | 500 GiB |

Charges are **prorated daily**, so a registry brought up for a week costs
about $1.17.

### The other two meters

- **Data Stored — $0.10/GB/month**, billed only *above* the SKU's included
  storage. On Basic that is 10 GiB; a handful of Spring Boot images will not
  approach it. In practice you pay the flat $5.07 and nothing else.
- **Task vCPU Duration — $0.0001/vCPU-second**, billed only if you use ACR
  Tasks for cloud-side image builds. Building locally and pushing does not
  touch this meter.

### Why Basic

`terraform/modules/acr/main.tf` hard-codes `sku = "Basic"` in a `locals`
block, so changing tiers is a code edit rather than a variable. Basic is the
right default: **managed-identity pull works on every SKU.** Standard only
buys more included storage and throughput; Premium buys private endpoints,
geo-replication, and content trust. Upgrade only if you add a private endpoint
against the `privatelink.azurecr.io` zone, which module 02 provisions (note
module 02 is not part of this runbook and is currently torn down).

### Total for this runbook

**~$5.07/month** — the registry and nothing else. Module 01's five resource
groups and module 04's UAMI are both free, so adding them to the provision
sequence costs nothing.

---

## 9. Safety notes

Applies to both modules in this runbook.

- **`apply-` and `destroy-` are `-auto-approve`; `plan-` is not.** Always run
  `plan-` first and read it. That is the only gate you get.
- **`apply-<name>` ignores the plan you reviewed.** `plan-acr` writes a
  `tfplan` file, but `apply-acr` re-plans from scratch and never reads it.
  There is a window in which the applied plan differs from the reviewed one.
  To apply exactly what you inspected, bypass Make:

  ```bash
  cd terraform/envs/dev/06-acr && terraform apply tfplan
  ```

- **Do not run bare `make destroy` here.** That is the whole-estate teardown
  (12 → 01). It would delete all five resource groups along with the
  registry, and runs the orphan sweep and Key Vault purge check you do not
  need.
- **Editing `acr_name` renames the registry.** azurerm implements an ACR
  rename as destroy-and-recreate: every image is lost and every reference to
  the old login server breaks. Combined with `-auto-approve`, treat any edit
  to `terraform/envs/dev/06-acr/terraform.tfvars` as a MAJOR change per
  `RELEASING.md`, and always `make plan-acr` first.
- **Changing `env` or `location` in `env.tfvars` forces replacement.** Both
  are baked into resource names/locations. Combined with `-auto-approve`, an
  edit there turns a routine apply into a destroy-and-recreate. Harmless while
  the RGs are empty; not harmless once images are in the registry.
- **A `VERSION` bump shows a pending `~ tags` diff on every resource.** Each
  module root stamps `release = local.release`, read from the repo-root
  `VERSION` file. That diff is the intended signal, not a bug, and tag changes
  are in-place updates in `azurerm` — a version bump never recreates a
  resource.

---

## 10. Quick reference

```bash
# Provision — safe from any starting state; 01 is a no-op if already applied
make plan-resource-groups    && make apply-resource-groups
make plan-managed-identities && make apply-managed-identities
make plan-acr                && make apply-acr

# Confirm the name (always rubensdevacr.azurecr.io in dev)
cd terraform/envs/dev/06-acr && terraform output -raw acr_login_server

# Destroy
make destroy-acr
make destroy-managed-identities   # optional
```

Related docs:

- `.github/workflows/provision-acr.yml` — the CI equivalent of §4, reusable
  from an application repository
- `docs/PROVISIONING_PLAN.md` — §4 dependency map, §12 passwordless auth,
  §15 full-teardown procedure
- `terraform/envs/dev/06-acr/README.md` — the by-hand `terraform` equivalents
- `terraform/envs/dev/04-managed-identities/README.md` — UAMI verification
- `terraform/INITIAL_SETUP.md` — one-time SP setup and `ARM_*` variables
- `CLAUDE.md` — current estate status
