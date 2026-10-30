# Resource Naming Reference

Every Azure resource this estate provisions is named after the Microsoft Cloud
Adoption Framework (CAF) form:

```
<resource type>-<workload>-<environment>-<region>   e.g. rg-rgomesapp-lab-eus2
```

Three inputs decide the whole namespace: `workload` (default `rgomes`), `env`
(`lab`, `dev`) and `location`, which becomes a short
[region code](#region-codes). `workload` and `env` live in
`terraform/envs/<env>/env.tfvars`; `location` comes from `TF_VAR_location`.

## The two rules that are not obvious

**Purposes are folded onto the workload token, not dash-separated.** Several
resources come as a set — six resource groups by lifecycle purpose, three
subnets. CAF's three-token form has no slot for that fourth idea, so the set
key is concatenated onto the workload: `rg-rgomesapp-lab-eus2`, not
`rg-rgomes-app-lab-eus2`. Every name in the estate is therefore exactly four
tokens — except container apps, a
[second exception](#a-second-exception-container-apps).

**There are no random suffixes.** Key Vault, Storage, Log Analytics, Service Bus
and PostgreSQL used to append four hex characters for global uniqueness. They no
longer do, so any name can be derived from `env.tfvars` without reading state.
What that costs is in [Soft-delete](#soft-delete-is-now-an-operational-concern)
below — read it before your first teardown.

## Name table

Workload `rgomes`, environment `lab`.

| Resource                  | Pattern                                               | Example                                                                                                                                                                           | Built in                            |
|---------------------------|-------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------|
| Resource groups (6)       | `rg-<workload><purpose>-<env>-<region>`               | `rg-rgomesplatform-lab-eus2`<br>`rg-rgomesnetwork-lab-eus2`<br>`rg-rgomesdata-lab-eus2`<br>`rg-rgomesapp-lab-eus2`<br>`rg-rgomesobservability-lab-eus2`<br>`rg-rgomesai-lab-eus2` | `modules/resource-groups`           |
| Virtual network           | `vnet-<workload>-<env>-<region>`                      | `vnet-rgomes-lab-eus2`                                                                                                                                                            | `modules/networking`                |
| Subnets (3)               | `snet-<workload><purpose>-<env>`                      | `snet-rgomesapp-lab`, `snet-rgomespg-lab`, `snet-rgomespe-lab`                                                                                                                    | `modules/networking`                |
| NSGs (3)                  | `nsg-<workload><purpose>-<env>`                       | `nsg-rgomesapp-lab`                                                                                                                                                               | `modules/networking`                |
| VNet links (5)            | `vnet-link-<workload><zone>-<env>`                    | `vnet-link-rgomeskv-lab`                                                                                                                                                          | `modules/networking`                |
| Log Analytics             | `log-<workload>-<env>-<region>`                       | `log-rgomes-lab-eus2`                                                                                                                                                             | `modules/log-analytics`             |
| Managed identity          | `id-<workload>app-<env>-<region>`                     | `id-rgomesapp-lab-eus2`                                                                                                                                                           | `modules/managed-identities`        |
| Key Vault                 | `kv-<workload>-<env>-<region>`                        | `kv-rgomes-lab-eus2`                                                                                                                                                              | `modules/key-vault`                 |
| Container registry        | *see [exception](#the-one-exception-acr)*             | `crrgomesdev01`                                                                                                                                                                   | `modules/acr`                       |
| Storage account           | `st<workload>app<env><region>`                        | `strgomesapplabeus2`                                                                                                                                                              | `modules/storage`                   |
| Service Bus               | `sb-<workload>msg-<env>-<region>`                     | `sb-rgomesmsg-lab-eus2`                                                                                                                                                           | `modules/service-bus`               |
| PostgreSQL                | `psql-<workload>-<env>-<region>`                      | `psql-rgomes-lab-eus2`                                                                                                                                                            | `modules/postgresql`                |
| Container App Env         | `cae-<workload>-<env>-<region>`                       | `cae-rgomes-lab-eus2`                                                                                                                                                             | `modules/container-app-environment` |
| Container apps            | *see [exception](#a-second-exception-container-apps)* | `ca-api-lab-eus2`                                                                                                                                                                 | `modules/container-apps`            |
| Application Insights      | `appi-<workload>-<env>-<region>`                      | `appi-rgomes-lab-eus2`                                                                                                                                                            | `modules/monitoring`                |
| Action group              | `ag-<workload>ops-<env>-<region>`                     | `ag-rgomesops-lab-eus2`                                                                                                                                                           | `modules/monitoring`                |
| Action group `short_name` | `<workload>ops`                                       | `rgomesops`                                                                                                                                                                       | `modules/monitoring`                |
| Foundry resource          | `aif-<workload>ai-<env>-<region>`                     | `aif-rgomesai-lab-eus2`                                                                                                                                                           | `modules/foundry`                   |
| Foundry project           | `proj-<workload>ai-<env>-<region>`                    | `proj-rgomesai-lab-eus2`                                                                                                                                                          | `modules/foundry`                   |
| Foundry App Insights      | `appi-<workload>ai-<env>-<region>`                    | `appi-rgomesai-lab-eus2`                                                                                                                                                          | `modules/foundry`                   |

The storage account is the one name with no dashes — Azure forbids them there —
so its four tokens simply run together in the same order.

Names **not** composed from workload and env, deliberately:

- **Private DNS zones** (`privatelink.vaultcore.azure.net`, …) are dictated by
  Azure; a private endpoint will not resolve against anything else.
- **Blob containers, PostgreSQL databases and container names** are the app name
  from `var.apps`, because module 12 wires them into apps as env vars.
- **Firewall rules and diagnostic settings** (`allow-azure-services`,
  `diag-to-law`) are scoped inside their parent and describe what they do.
- **The state backend**, which follows its own shape — see
  [below](#the-state-backend).

## Region codes

Azure publishes no short code for a region; `az account list-locations`
returns only the name (`eastus2`) and display name (`East US 2`). Codes here
are the lowercase Azure Backup geo-codes from
[Geo-code mapping](https://learn.microsoft.com/en-us/azure/backup/scripts/geo-code-list).
The map lives in `terraform/modules/region-code/region-codes.json`, read by
both Terraform and `scripts/region-code.sh`. It is maintained by hand; add a
region from that page before using it.

| Region           | Code   |
|------------------|--------|
| `eastus`         | `eus`  |
| `eastus2`        | `eus2` |
| `westus`         | `wus`  |
| `westus2`        | `wus2` |
| `westus3`        | `wus3` |
| `centralus`      | `cus`  |
| `northcentralus` | `ncus` |
| `southcentralus` | `scus` |
| `canadacentral`  | `cnc`  |
| `northeurope`    | `ne`   |
| `westeurope`     | `we`   |
| `swedencentral`  | `sdc`  |
| `uksouth`        | `uks`  |

## Length budgets

`workload` validates at 2–16 lowercase alphanumeric characters, `env` at 2–10,
and region codes are 2–4. Three composed names can still overflow a legal set,
so the modules assert them at plan time rather than letting Azure reject them
mid-apply:

| Name                      | Cap | At `rgomes`/`lab`         | Precondition                 |
|---------------------------|-----|---------------------------|------------------------------|
| Storage account           | 24  | `strgomesapplabeus2` (18) | `modules/storage/main.tf`    |
| Key Vault                 | 24  | `kv-rgomes-lab-eus2` (18) | `modules/key-vault/main.tf`  |
| Action group `short_name` | 12  | `rgomesops` (9)           | `modules/monitoring/main.tf` |

The storage account is the binding constraint: with a 3-character `env` and a
4-character region code, `workload` fits only up to 12 characters.

## Soft-delete is now an operational concern

Deterministic names mean a rebuild asks for the *same* name every time. Three
resources hold a deleted name in a recycle bin, and a rebuild inside that window
fails on it. The old random suffixes made this impossible; now it is the normal
failure mode of a teardown-then-reprovision.

| Resource      | Window                                | Way out                                                                         |
|---------------|---------------------------------------|---------------------------------------------------------------------------------|
| Key Vault     | 7 days (`soft_delete_retention_days`) | `az keyvault purge` — `make destroy` already does this                          |
| Log Analytics | 14 days                               | `az monitor log-analytics workspace delete --force`                             |
| PostgreSQL    | up to 7 days                          | no `list-deleted` exists; `az postgres flexible-server revive-dropped` recovers |

Storage, Service Bus, ACR, Container App Environment and the resource groups
release their names immediately. The full procedure is in
[TEARDOWN.md](TEARDOWN.md#purge-soft-deleted-names-before-reprovisioning).

The second consequence is collision. Key Vault, Storage, Service Bus,
PostgreSQL and ACR names are globally unique across every Azure tenant, so a
generic `workload` can be taken by a stranger. Apply fails fast with an
availability error rather than quietly landing elsewhere — pick a distinctive
token.

## Changing `workload` or `env`

`name` is ForceNew on every resource here. Changing either value against a live
estate is a **destroy and recreate**, not a rename — and because the estate
spans fifteen state files that only know each other through remote-state reads,
the result is a broken estate rather than a renamed one. Change it at first
provision, or after a full teardown.

Three places hold the `rgomes` default and must agree: every module's `workload`
variable, `WORKLOAD` in the `Makefile` (which names the observability RG in the
orphan sweep), and the `|| 'rgomes'` fallback in every create/destroy
workflow. `acr-create.yml`, `cae-create.yml`, and `aca-create.yml` guard this
explicitly — each refuses a run whose `TF_VAR_workload` disagrees with the RG
name already in module 01's state.

Note that `workload` does **not** change between environments. `dev` and `lab`
share `rgomes` and are told apart by the trailing token alone.

## The first exception: ACR

`modules/acr` takes its name verbatim from `var.acr_name` (`TF_VAR_acr_name`)
instead of composing one. Two reasons, both about the name being typed rather
than derived: it is baked into every image tag, `docker push` and
`apps_image_map` entry, and it is reachable from a `workflow_dispatch` input so
CI can point a run at an existing registry.

Follow the convention anyway, spelled without the dashes ACR forbids:
`cr<workload><env>` → `crrgomesdev`. The current values are `crrgomesdev01` in
dev and `crrgomeslab02` in lab; the trailing digits are a collision escape
hatch, which is the second reason this stays a human-chosen literal.

## A second exception: container apps

`modules/container-apps` omits the workload token: `ca-<app>-<env>-<region>`,
e.g. `ca-api-lab-eus2`, not `ca-rgomesapi-lab-eus2`. `<app>` (an entry in
`var.apps`) is already the leaf identifier callers type and read back from
`app_names`, so folding a fixed, estate-wide `workload` token onto it added a
prefix without adding information. Every other resource in the estate still
folds in `workload`.

## The state backend

`terraform/bootstrap-backend/` provisions three names that follow the CAF form
loosely, with one deliberate wrinkle:

| Coordinate      | Name                   | Shape                                       |
|-----------------|------------------------|---------------------------------------------|
| Resource group  | `rg-rgomestfstate-lab` | `rg-<workload><purpose>-<env>`              |
| Storage account | `strgomestfstate02`    | `st<workload><purpose>` + a collision digit |
| Blob container  | `rgomes-lab-tfstate`   | `<workload>-<env>-tfstate`                  |

**The `-lab` token on the resource group is a naming concession, not a scoping
one.** The RG and storage account are shared by every environment — separation
happens one level down, at the container, which is why the container is the
only coordinate whose env token means anything. A `dev` estate's state blobs
live in a container inside this lab-named group. Read the RG name as *the
workload's state store*, not as *lab's*. `bootstrap-backend/variables.tf`
carries the same note, and for the same reason its `tags` default still stamps
no `environment` key.

The storage account keeps its trailing `02` for the reason ACR does: the name
is globally unique across every Azure tenant, so a taken name needs a human to
pick the next one.

Three further things about these names, unlike the rest of the estate:

- They are **not composed** from `workload` and `env` at plan time. They are
  literals, because a `terraform { backend }` block cannot interpolate — the
  values live in `bootstrap-backend/backend.tf`, `bootstrap-backend/variables.tf`
  and both `envs/<env>/backend.hcl`, and all four must agree by hand.
- `bootstrap/backend.tfstate` shares the container with the fifteen estate state
  blobs, and stays there. The backend's own state spans environments.
- **Renaming them is a state migration, not an edit.** An Azure resource group
  and storage account cannot be renamed in place, and Terraform will not follow
  a renamed backend: the new store has to be created, every state blob copied
  across, and each root re-inited with `-reconfigure`. See
  [TF_BOOTSTRAP_CREATE.md](TF_BOOTSTRAP_CREATE.md).

