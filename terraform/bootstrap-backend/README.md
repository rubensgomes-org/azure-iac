# terraform/bootstrap-backend

This is the Terraform bootstrap stage (bootstrap-backend) module. This module
implements Azure provisioning operations to create the resource group and
storage resources required by Terraform. This stage MUST be run prior
to anything else, and it is therefore named "bootstrap-backend".

The following Terraform backend initial resources are created:

- resource group (e.g., rg-tfstate)
- storage account (e.g., sttfstaterubens01)
- storage container (e.g., tfstate)

Once this module is run, Terraform will be able to use the corresponding
blob storage to store the state files of Terraform configurations.

## Configuration Steps Prerequisites

1. Ensure ARM credential environment variables are found:

    ```bash
    env | grep ARM
    # should display:
    # ARM_CLIENT_ID=<SECRET_INFO>
    # ARM_TENANT_ID=<SECRET_INFO>
    # ARM_CLIENT_SECRET=<SECRET_INFO>
    # ARM_SUBSCRIPTION_ID=<SECRET_INFO>
    ```

2. Ensure the storage_account_id (e.g., TF_STORAGE_ACCOUNT) name is available:

    ```bash
    az login
    TF_STORAGE_ACCOUNT="sttfstaterubens01"
    az storage account check-name  \
      --name ${TF_STORAGE_ACCOUNT} \
      --query nameAvailable -o tsv
    # if false it means that this storage account is already provisioned
    ```

### Chicken-and-egg workflow

The “gotcha” here is the classic chicken‑and‑egg problem: you can’t use an Azure
Blob backend until the storage account/container exist. Once you've already
created them (using local state), you’re now in the perfect position to migrate
that local state into the blob container.

See comments in the [backend.tf](./backend.tf) file.

#### Pass 1 - Local state:

1. Comment out (or remove) this entire `terraform { backend "azurerm" {} }`
   from the [backend.tf](./backend.tf) file block.

2. Bootstrap backend by creating the Terraform remote state backend (one-time).
   `terraform apply` creates the RG, Storage Account, container, RBAC, and
   optional RG lock (see main.tf). State lives in `./terraform.tfstate`.

    ```shell
    cd $(git rev-parse --show-toplevel) || exit
    cd terraform/bootstrap-backend
    terraform init --upgrade || exit
    terraform validate || exit
    export TF_LOG='INFO'
    export TF_LOG_PATH='/tmp/terraform.log'
    # the following command may take a few minutes to run !!!
    terraform plan -out bootstrap.tfplan
    terraform apply bootstrap.tfplan
    ```

### Pass 2 - Migrate state to Azure:

1. Ensure you have created Terraform backend storage resources (e.g., resource
   group, storage account, and container) in Azure

   - resource group:

       ```shell
       az group list --output table
       ```

   - storage account:

       ```shell
       export TF_RESOURCE_GROUP="rg-tfstate"
       az storage account show \
       --name "${TF_STORAGE_ACCOUNT}" \
       --resource-group "${TF_RESOURCE_GROUP}" \
       -o table
       ```

   - container:

       ```shell
       az storage container list \
       --account-name "${TF_STORAGE_ACCOUNT}" \
       --output table
       ```

2. Re-enable [backend.tf](./backend.tf) file by uncommenting the `terraform 
{ backend "azurerm" {} }` section.

3. Ensure 'bootstrap-backend/backend.tf' has the following:

   ```text
   terraform {
     backend "azurerm" {
       resource_group_name  = "rg-tfstate"
       storage_account_name = "sttfstaterubens01"
       container_name       = "tfstate"
   
       # IMPORTANT: choose a unique key for the BOOTSTRAP state.
       # Do not reuse the same key as your phase1 state.
       key = "bootstrap/backend.tfstate"
   
       # We want to use the Terraform SP + Secrets created in the
       # project [INITIAL_SETUP.md](../INITIAL_SETUP.md) to access
       # the Blob Storage
       use_azuread_auth = false
     }
   }
   ```

4. Run the following command locally:

   ```bash
   # answer yes at the prompt
   terraform init -migrate-state
   ```

   - **From then on, every plan/apply reads and writes to the blob.**

5. To destroy the above applied plan:

    - ONLY RUN THIS WHEN YOU KNOW ALL THE OTHER AZURE RESOURCES HAVE BEEN
      DELETED!!!

    ```bash
    cd $(git rev-parse --show-toplevel) || exit
    cd terraform/bootstrap-backend
    export TF_LOG=INFO
    terraform destroy -auto-approve
    ```

## Issue with Terraform local state in GitHub Actions

Terraform only manages what’s recorded in its state file. If the state doesn’t
contain the RG, Terraform assumes it doesn’t exist and tries to create it. Azure
rejects that because it already exists, and Terraform tells you to import.

That means Terraform is using the local backend. In GitHub Actions, runners are
ephemeral, so unless you persist the state somehow, each run starts with an
empty state → destroy can’t destroy anything and apply tries to recreate
existing resources, which then fails. This is exactly why pipelines that use
local state on ephemeral runners often fail on the second run.

To fix the issue we need to import the existing resources (e.g., resource group,
storage account, and container name) into Terraform local state:

   ```bash
   terraform init -upgrade
   export TF_RESOURCE_GROUP="rg-tfstate"
   export TF_STORAGE_ACCOUNT="sttfstaterubens01"
   export TF_CONTAINER="tfstate"
   # import resource group
   terraform import azurerm_resource_group.tfstate \
      "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${TF_RESOURCE_GROUP}"
   # import storage account
   terraform import azurerm_storage_account.tfstate \
      "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${TF_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${TF_STORAGE_ACCOUNT}"
   # import container name
   terraform import azurerm_storage_container.tfstate \
      "https://${TF_STORAGE_ACCOUNT}.blob.core.windows.net/${TF_CONTAINER}"
   terraform plan -out=bootstrap.tfplan
   terraform apply bootstrap.tfplan
   ```

## The `.terraform.lock.hcl` dependency lock file

`terraform init` writes a file called `.terraform.lock.hcl` in this directory.
It is Terraform's **dependency lock file** and it records the exact provider
versions and provider-binary checksums that were selected the last time init
ran successfully.

A typical entry looks like this:

```hcl
provider "registry.terraform.io/hashicorp/azurerm" {
  version     = "4.80.0"
  constraints = "~> 4.80"
  hashes = [
    "h1:...",
    "zh:...",
    # ...
  ]
}
```

Each field means:

- `version` — the exact version Terraform picked on the last init, from the
  range allowed by `versions.tf`. The `4.80.0` shown above is illustrative;
  your lock file will show whatever `versions.tf` currently allows.
- `constraints` — the constraint that was in effect at that time.
- `hashes` — cryptographic checksums (`h1:` = the modern hash format;
  `zh:` = the legacy zip hashes) of the provider binary. On every subsequent
  `init`, Terraform re-verifies the downloaded provider against these hashes
  and refuses to use a binary that does not match.

### Commit this file to source control

The lock file MUST be committed to git alongside the `.tf` files. Reasons:

1. **Reproducibility.** Every teammate and CI runner installs the same
   provider version — otherwise whoever runs `init` first "wins" and others
   silently pick up newer builds.
2. **Supply-chain safety.** The recorded hashes protect against a tampered
   provider being served from the registry or a mirror.
3. **Deliberate upgrades.** Provider version bumps show up as a reviewable
   diff in a PR (`version = "4.80.0"` → `"4.90.0"`) instead of drifting
   silently on someone's laptop.
4. **CI stability.** Pipelines that run `terraform init -lockfile=readonly`
   require the committed file and will fail without it.

### Regenerating the lock file

Terraform manages this file automatically. The two commands that touch it:

```bash
# Install providers that satisfy the current lock file (default behaviour).
# Fails if versions.tf constraints and the lock file no longer agree.
terraform init

# Re-evaluate versions.tf, pick the newest satisfying provider versions,
# and rewrite the lock file. Use this after editing versions.tf or when
# intentionally bumping providers.
terraform init -upgrade
```

After `-upgrade`, review the diff to `.terraform.lock.hcl`, commit it in the
same PR as the `versions.tf` change, and note the version bump in the PR
description.

### Do NOT hand-edit the lock file

The file's own header says *"Manual edits may be lost in future updates."*
Comments and manual reformatting are wiped by the next `-upgrade`. If you
need to force a specific provider version, edit `versions.tf` and run
`terraform init -upgrade` — do not edit the lock file directly.

### Files in the `.terraform*` family — what to commit

| Path                  | Commit? | Why                                            |
|-----------------------|---------|------------------------------------------------|
| `.terraform.lock.hcl` | Yes     | Dependency lock; see above.                    |
| `.terraform/`         | No      | Provider binary + module cache; regenerated.   |
| `terraform.tfstate*`  | No      | Actual state; lives in the Azure blob backend. |
| `*.tfplan`            | No      | Plan artifact; not portable between machines.  |

## Destroying the Terraform Backend

NEVER DESTROY THE BACKEND WHILE USING TERRAFORM TO STORE STATE ON THE BACKEND.
FROM NOW ON DO NOT EVER REMOVE THE BACKEND RESOURCES UNLESS YOU FOLLOW A VERY
RIGOROUS PROCEDURE BEFORE DOING SO.

Before destroying bootstrap backend resources, always do:

- Migrate state back to local first (safe teardown)
- Change backend to local
- terraform init -migrate-state
- terraform destroy