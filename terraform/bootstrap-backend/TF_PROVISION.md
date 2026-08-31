# Provisioning the Terraform bootstrap backend

Steps to create `terraform/bootstrap-backend/` — the resource group, Storage
Account, blob container and RBAC assignment that hold the remote state for every
other module in this repo.

Two things to know before starting:

- **This runs before everything else.** No module root under
  `terraform/envs/dev/` can `terraform init` until the container exists, so
  `make apply` cannot run at all until this completes.
- **A bootstrap starts from genuinely empty state.** It recovers nothing a
  previous teardown deleted. Any Azure resource still standing from before has
  to be `terraform import`ed back in.

## Prerequisites

You must first complete the steps in [INITIAL_SETUP](./INITIAL_SETUP.md)

- Ensure ARM_ environment is configured on your shell:

```bash
# ensure you have the ARM environment setup:
env | grep '^ARM_'
#   ARM_CLIENT_ID / ARM_TENANT_ID / ARM_CLIENT_SECRET / ARM_SUBSCRIPTION_ID
```

- Login as the SP user:

```bash
az login --service-principal \
  -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
az account set --subscription "$ARM_SUBSCRIPTION_ID"
az account show --query "{sub:name,id:id,tenant:tenantId}" -o table
```

- Ensure Storage Account name availability globally:

```bash
# TF backend storage account
TF_STORAGE_ACCOUNT='sttfstaterubens01'
az storage account check-name --name "${TF_STORAGE_ACCOUNT}" \
  --query nameAvailable -o tsv
# should return true if account name is available.
```

## 1. Procedure

Everything runs from this directory:

```bash
cd "$(git rev-parse --show-toplevel)/terraform/bootstrap-backend"
```

Set these once from the values in `terraform.tfvars` so the rest can be pasted
as-is:

```bash
TF_RESOURCE_GROUP='rg-tfstate'
TF_STORAGE_ACCOUNT='sttfstaterubens01'
```

### Pass 1 — create on local state

#### Step 1 — comment out the backend block

Open `backend.tf` and comment out the entire
`terraform { backend "azurerm" { ... } }` block (lines 45-101).

If you have arrived straight from a teardown it is already commented out.
Confirm rather than assume:

```bash
git diff backend.tf
```

#### Step 2 — init and validate

```bash
terraform init -upgrade
terraform validate
```

Confirm the local backend actually took effect:

```bash
# This file is populated after migrating from azurerm to local during teardown 
cat .terraform/terraform.tfstate
# local backend   → {"version": 3, "terraform_version": "..."}  (no "backend" key)
# azurerm backend → a "backend" object naming the storage account
```

If it still shows an azurerm backend, Step 1 did not take.

#### Step 3 — plan and read it

```bash
terraform plan -out=bootstrap.tfplan \
  -var backend_resource_group_name="${TF_RESOURCE_GROUP}" \
  -var storage_account_id="${TF_STORAGE_ACCOUNT}"
terraform show bootstrap.tfplan
```

Expect **4 to add, 0 to change, 0 to destroy**, and check the resource group's
`location` is the region you intend. Any `change` or `destroy` in a bootstrap
plan means there is stale local state — stop and work out why rather than
applying it.

#### Step 4 — apply

```bash
terraform apply bootstrap.tfplan
```

Applying the saved plan is preferable to a bare `terraform apply -auto-approve`:
what you reviewed in Step 3 is exactly what executes, with no second refresh in
between that could pick up a change.

---

### Pass 2 — migrate state into the container just created

#### Step 5 — restore the backend block

```bash
git checkout -- backend.tf
```

Restoring from git rather than hand-uncommenting guarantees the literals still
match `terraform.tfvars`. A mismatch surfaces at the next init as a "backend not
found" error.

#### Step 6 — migrate

```bash
terraform init -migrate-state
```

Answer `yes` at the prompt. Terraform detects the backend change and copies
`./terraform.tfstate` up into the `bootstrap/backend.tfstate` blob.

#### Step 7 — verify

Terraform's view and Azure's view:

```bash
terraform state list | grep -v '^data\.'    # → the 4 managed resources
terraform plan \
  -var backend_resource_group_name="${TF_RESOURCE_GROUP}" \
  -var storage_account_id="${TF_STORAGE_ACCOUNT}"

TF_RESOURCE_GROUP='rg-tfstate'
TF_STORAGE_ACCOUNT='sttfstaterubens01'

az group show -n "${TF_RESOURCE_GROUP}" --query location -o tsv
az storage container list --account-name "${TF_STORAGE_ACCOUNT}" \
   --auth-mode login -o table
az storage blob list --account-name "${TF_STORAGE_ACCOUNT}" \
  --container-name tfstate \
  --auth-mode login \
  --query "[].{name:name,size:properties.contentLength}" -o table
# → bootstrap/backend.tfstate, kilobytes not hundreds of bytes
```

`terraform plan` reporting **No changes** is the strongest single signal: it
proves the migrated state matches what is actually in Azure.

A state blob of a few hundred bytes is an empty shell holding only serial and
lineage — that means the migration did not move anything.

#### Step 8 — leave the tree in a known state

```bash
rm -f terraform.tfstate terraform.tfstate.backup bootstrap.tfplan
cd "$(git rev-parse --show-toplevel)" && git status --porcelain   # → empty
```

These are all gitignored, so none can be committed by accident, but delete them
anyway: a stale local `terraform.tfstate` is exactly what makes a later apply
try to recreate something Azure already has.

## 5. After the bootstrap

Every module root's `.terraform/` now holds a stale backend pointer. Clear them
unconditionally — this is purely local, works regardless of backend state, and
is uniform across all twelve roots:

```bash
rm -rf terraform/envs/dev/*/.terraform
make apply    # per-module init re-runs with -reconfigure -backend-config=../backend.hcl
```

Prefer this over `make init-<name>`, which contacts the storage account and so
only works once the backend is up. Its only cost is that the next `init`
re-downloads providers — `.terraform.lock.hcl` is committed, so versions stay
pinned.

Note the trap: `make validate` inits with `-backend=false` and leaves every
`.terraform/` on an empty local backend, which makes `terraform state list` and
`terraform output` return nothing. It is a syntax check, not preparation for
applying.













## 1. Why the step order matters

State cannot live in a container that does not exist yet — the chicken-and-egg
described at the top of `backend.tf`. So the module is applied in **two
passes**:

- **Pass 1** — backend block commented out, local state. Creates the RG, Storage
  Account, container and role assignment.
- **Pass 2** — backend block restored. `terraform init -migrate-state` copies
  `./terraform.tfstate` up into the container just created.

The load-bearing consequence:

> **`terraform init` against the azurerm backend fails when the Storage Account
> does not exist** — *Error retrieving keys for Storage Account*.

That is why pass 1 must run on the local backend, and it is the same constraint
that makes a CI bootstrap impossible (§7).

## 2. What gets created

Four managed resources, all declared in `main.tf`. Their names come from
`terraform.tfvars` in this directory:

| Address                                          | `main.tf` | Named by                                                                   |
|--------------------------------------------------|-----------|----------------------------------------------------------------------------|
| `azurerm_resource_group.tfstate`                 | 57-61     | `backend_resource_group_name` + `location`                                 |
| `azurerm_storage_account.tfstate`                | 85-129    | `storage_account_id`                                                       |
| `azurerm_storage_container.tfstate`              | 142-146   | `container_name`                                                           |
| `azurerm_role_assignment.state_blob_contributor` | 163-167   | scoped to the account; principal from `data.azurerm_client_config.current` |

`terraform state list` will show a **fifth** line,
`data.azurerm_client_config.current`. That is a data source, not a managed
resource. Count only what is managed:

```bash
terraform state list | grep -v '^data\.'   # → 4 lines
```

`main.tf` also declares `azurerm_management_lock.tfstate_rg_lock` under
`count = var.enable_rg_lock ? 1 : 0`. With that variable false the lock is
absent from state entirely.

### Inputs

Two values in `terraform.tfvars` **override the `variables.tf` default**. A run
that loses that file silently behaves differently:

| Variable                     | `variables.tf` default | `terraform.tfvars` |
|------------------------------|------------------------|--------------------|
| `location`                   | `centralus`            | `centralus`        |
| `storage_account_id`         | none (required)        | set                |
| `container_name`             | `tfstate`              | `tfstate`          |
| `replication_type`           | `LRS`                  | `LRS`              |
| `soft_delete_retention_days` | **`7`**                | **`2`**            |
| `enable_rg_lock`             | **`true`**             | **`false`**        |

`enable_rg_lock` is the one that bites: defaulting to `true` creates a
`CanNotDelete` lock, which then blocks the teardown in `TF_DESTROY.md`.



## 6. Gotchas

- **`terraform init` fails with *Error retrieving keys for Storage Account*.**
  The backend block is active but the account does not exist yet. That is pass
  1's entire reason for existing — comment the block out.

- **`terraform init -migrate-state` reports success but moves nothing.** Run
  while the backend block is still commented out, it is an already-local no-op
  that prints reassuring output. The blob check in Step 7 is what catches this.

- **`terraform state list` comes back empty and the backend looks
  unprovisioned.** Cause: a previous `make validate` in this directory left
  `.terraform/` pointed at an empty local backend, so `state list` and `output`
  both return nothing. Re-init before trusting either.
  `.terraform/terraform.tfstate` containing a `backend` key is the marker that a
  directory is init'd against azurerm.

- **Three resources create and the role assignment fails.** The Service
  Principal lacks `User Access Administrator`. Grant it and re-run; the other
  three refresh unchanged and drop out of the plan.

- **The Storage Account name is already taken.** Renaming is not a one-line
  change: `backend.tf:69`, `terraform.tfvars:51`,
  `terraform/envs/dev/backend.hcl:24`, **and ~35 `data.terraform_remote_state`
  literal pairs across the eleven module roots** `02-networking` …
  `12-monitoring`. If the name was yours moments ago, wait for Azure to release
  it instead.

- **Do not change `location` to "move" the backend.** `location` is ForceNew on
  `azurerm_resource_group`, so editing it plans a destroy + create of the
  backend RG — the whole of `TF_DESTROY.md`, executed by accident from what
  looks like a one-word edit. Azure also cannot move a Storage Account between
  regions, so it would need a new globally-unique name too.

- **`enable_rg_lock` defaults to `true`.** Only `terraform.tfvars` holds it
  false. A bootstrap run without that file creates a `CanNotDelete` lock that
  then blocks teardown.

## 7. There is no CI path, deliberately

The bootstrap is hand-operated. Do not add a workflow for it.

Per §1, the azurerm backend cannot init against a Storage Account that does not
exist, so a CI job could never perform pass 1 — only converge drift on a backend
that is already up. Pass 2 is `terraform init -migrate-state`, which prompts;
CI gets past that only with `-force-copy`, which turns the one irreversible
state-migration decision into an unattended flag.

The teardown has the same problem in reverse — see `TF_DESTROY.md` — and
`docs/PROVISIONING_PLAN.md` §15 records the reasoning for both directions.
