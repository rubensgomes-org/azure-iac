# TF_DESTROY.md — Destroying the Terraform state backend

Steps to tear down `terraform/bootstrap-backend/` — the resource group, Storage
Account, blob container and RBAC assignment that hold the remote state for every
other module in this repo.

Two things to settle before starting:

- **The estate must already be at zero.** `make destroy` from the repo root
  walks modules 12 → 01 and never touches this directory. Run it first; see
  `docs/PROVISIONING_PLAN.md` for the full teardown procedure.
- **This is a one-way door.** Deleting the Storage Account deletes every module
  state blob inside it, along with the versioning and soft-delete policies that
  would otherwise protect them — those guard blobs *within* a live account and
  do not survive the account itself. There is no purge or restore step.

## 1. Why the step order matters

The backend module stores its own state inside the very container it manages —
the chicken-and-egg described at the top of `backend.tf`. That makes a naïve
teardown self-destructive:

> **NEVER run `terraform destroy` in this directory while `backend.tf` still
> points at the azurerm backend.**

## 2. What gets destroyed

Four managed resources, all declared in `main.tf`. Their names come from
`terraform.tfvars` in this directory:

| Address                                          | Named by                      | Note                                                                       |
|--------------------------------------------------|-------------------------------|----------------------------------------------------------------------------|
| `azurerm_resource_group.tfstate`                 | `backend_resource_group_name` | `location` also from `terraform.tfvars`                                    |
| `azurerm_storage_account.tfstate`                | `storage_account_id`          | Globally-unique name; released on delete                                   |
| `azurerm_storage_container.tfstate`              | `container_name`              | Holds every module's state blob                                            |
| `azurerm_role_assignment.state_blob_contributor` | —                             | `Storage Blob Data Contributor`, scoped to the account, so it dies with it |


```bash
terraform state list | grep -v '^data\.'   # → 4 lines
```

## 3. Prerequisites

```bash
# 1. Terraform authenticates via the Service Principal (see INITIAL_SETUP.md).
#    These environment variables must already be exported in the shell:
env | grep '^ARM_'
#   ARM_CLIENT_ID=<SECRET>
#   ARM_TENANT_ID=<SECRET>
#   ARM_CLIENT_SECRET=<SECRET>
#   ARM_SUBSCRIPTION_ID=<SECRET>
#   ARM_SUBSCRIPTION_NAME=<subscription-name>

# 2. The az CLI authenticates SEPARATELY — it does NOT inherit ARM_*.
az account show >/dev/null || az login --tenant "${ARM_TENANT_ID}"

# 3. Ensure you are using the right subscription
az account set --subscription "${ARM_SUBSCRIPTION_ID}"

# 4. No estate module may still be applied.
az group list --query "[?starts_with(name, 'rg-dev')].name" -o tsv
#   must return nothing

# 5. For sub-3cloud-lab use the following command:
az group list \
  --query "[?starts_with(name, 'rg-dev') && ends_with(name, 'rubens')].name" \
  -o tsv
#   must return nothing
```

Destroying the backend while any `rg-dev-*` module is still applied strands
those resources: their state blobs go away with the container, so Terraform can
no longer see or delete them. They keep billing.

## 4. Procedure

Everything runs from this directory:

```bash
cd "$(git rev-parse --show-toplevel)/terraform/bootstrap-backend"
```

The verification commands below refer to the backend by name. Set these once
from the values in `terraform.tfvars` so the rest of the procedure can be pasted
as-is:

```bash
# value of backend_resource_group_name in terraform.tfvars
TF_RESOURCE_GROUP='rg-tfstate'
# value of storage_account_id in terraform.tfvars
TF_STORAGE_ACCOUNT='sttfstaterubens01'
```

### Step 1 — comment out the backend block

Open `backend.tf` and comment out the entire
`terraform { backend "azurerm" { ... } }` block. Commenting it out is preferred
over deleting it: the block carries the literals you would need to retype in
order to re-bootstrap, and the diff makes the temporary state of the tree
obvious in `git status`.

With no `backend` block, Terraform falls back to the local backend.

### Step 2 — pull state down to a local file

```bash
# You need to remove the following file first:
cd "$(git rev-parse --show-toplevel)"
rm -rf terraform/bootstrap-backend/.terraform
# proceed now...
cd "$(git rev-parse --show-toplevel)/terraform/bootstrap-backend"
terraform init -migrate-state
```

Answer `yes` at the prompt. Terraform detects the backend change and copies the
blob's contents into `./terraform.tfstate`.

**Verify the migration actually moved something before going further** — this is
the last point at which a mistake is still cheap:

```bash
terraform state list            # → the 4 managed resources + the data source
ls -l terraform.tfstate         # → kilobytes, not a few hundred bytes
```

A state file of a few hundred bytes is an empty shell holding only serial and
lineage. If you see that, the migration did not happen, and a destroy from here
would delete nothing while reporting success. Do not proceed.

Also confirm the local backend took effect:

```bash
cat .terraform/terraform.tfstate
# local backend   → {"version": 3, "terraform_version": "..."}  (no "backend" key)
# azurerm backend → a "backend" object naming the storage account
```

### Step 3 — plan the destroy and read it

```bash
terraform plan -destroy -out=destroy.tfplan
  -var backend_resource_group_name="${TF_RESOURCE_GROUP}" \
  -var storage_account_id="${TF_STORAGE_ACCOUNT}"
terraform show destroy.tfplan
```

`terraform.tfvars` is auto-loaded by filename, so no `-var-file` is needed.

Expect exactly four resources to be destroyed and nothing else. Any `create` or
`replace` in a destroy plan means the state does not match reality — stop and
work out why rather than applying it.

### Step 4 — destroy

```bash
terraform apply destroy.tfplan
```

Applying the saved plan is preferable to a bare `terraform destroy
-auto-approve`: what you reviewed in Step 3 is exactly what executes, with no
second refresh in between that could pick up a change.

If this fails partway, the local state file is still accurate. Fix the cause and
re-run from Step 3; already-deleted resources refresh to absent and drop out of
the plan.

### Step 5 — verify

```bash
# Terraform's view: no managed resources left.
terraform state list | grep -v '^data\.'   # → no output

# value of backend_resource_group_name in terraform.tfvars
TF_RESOURCE_GROUP='rg-tfstate'
# value of storage_account_id in terraform.tfvars
TF_STORAGE_ACCOUNT='sttfstaterubens01'

# Azure's view: the backend's own resources are gone.
az group exists -n "${TF_RESOURCE_GROUP}"           # → false
az storage account show -n "${TF_STORAGE_ACCOUNT}"   # → ResourceNotFound
```

`ResourceGroupNotFound` / `ResourceNotFound` here are success, not errors.

### Step 6 — leave the tree in a known state

`terraform.tfstate`, `terraform.tfstate.backup`, `.terraform/` and `*.tfplan`
are all gitignored, so none of them can be committed by accident. The only
tracked file you changed is `backend.tf`.

Decide deliberately what to do with it:

- **Re-bootstrapping soon** — leave the block commented out. Pass 1 of the
  bootstrap needs the local backend anyway.
- **Done for now** — restore `backend.tf` so the committed tree matches what a
  fresh clone should look like, and delete the local state artifacts. They
  describe resources that no longer exist, and a stale `terraform.tfstate` is
  exactly what makes a later `apply` try to recreate something Azure already
  has.

  ```bash
  git checkout -- backend.tf
  rm -f terraform.tfstate terraform.tfstate.backup destroy.tfplan
  ```

The reverse of this document — the two-pass re-bootstrap — is in this
directory's `README.md` and in the header comment of `backend.tf`.

## History

```text
    1  history -w
    2  pushd github/dev/iac/azure-iac/
    3  env | grep '^ARM_'
    4  az account show >/dev/null || az login --tenant "${ARM_TENANT_ID}"
       # ensure you are using the right subscription
       az account set --subscription "${ARM_SUBSCRIPTION_ID}"
    5  az group list --query "[?starts_with(name, 'rg-dev')].name" -o tsv
    6  cd "$(git rev-parse --show-toplevel)/terraform/bootstrap-backend"
    # --- >>> Comment out the backend.tf file <<< ---
    7  terraform init -migrate-state
    8  terraform state list            # → the 4 managed resources + the data source
    9  ls -l terraform.tfstate         # → kilobytes, not a few hundred bytes
   10  cat .terraform/terraform.tfstate
   11  terraform plan -destroy -out=destroy.tfplan
   12  terraform show destroy.tfplan
   13  terraform apply destroy.tfplan
   14  # value of backend_resource_group_name in terraform.tfvars
   15  TF_RESOURCE_GROUP='rg-tfstate'
   16  # value of storage_account_id in terraform.tfvars
   17  TF_STORAGE_ACCOUNT='sttfstaterubens01'
   18  az group exists -n "${TF_RESOURCE_GROUP}"           # → false
   19  az storage account show -n "${TF_STORAGE_ACCOUNT}"  # → ResourceNotFound
   # --- >>> Uncomment out the backend.tf file <<< ---
      git checkout -- backend.tf
      rm -f terraform.tfstate terraform.tfstate.backup destroy.tfplan
   20  vim backend.tf 
   21  ls -l terraform.* destroy.*
```