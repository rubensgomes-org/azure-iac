# terraform/bootstrap-backend

The Terraform bootstrap stage. It provisions the resource group, storage
account and blob container that hold the remote state for every other module
in this repo. It MUST be applied before anything else — hence the name.

The following Terraform backend initial resources are created. All three are
named from the environment, so the values below are whatever you exported in
[INITIAL_SETUP.md](../INITIAL_SETUP.md) — never hardcode them here:

- resource group — `TF_VAR_backend_resource_group_name`
- storage account — `TF_VAR_storage_account_id` (globally unique)
- storage container — `TF_VAR_container_name`

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

2. Ensure the storage account name is still available. Storage account names
   are globally unique across Azure:

    ```bash
    az login --tenant "${AZURE_TENANT_ID}"
    az storage account check-name \
      --name "${TF_VAR_storage_account_id}" \
      --query nameAvailable -o tsv
    # if false it means that this storage account is already provisioned
    ```

### Chicken-and-egg workflow

The "gotcha" here is the classic chicken-and-egg problem: you can't use an Azure
Blob backend until the storage account/container exist. Once you've already
created them (using local state), you're now in the perfect position to migrate
that local state into the blob container.

See comments in the [backend.tf](./backend.tf) file.

#### Pass 1 - Local state

1. Comment out (or remove) the entire `terraform { backend "azurerm" {} }`
   block from the [backend.tf](./backend.tf) file.

2. Bootstrap backend by creating the Terraform remote state backend (one-time).
   `terraform apply` creates the RG, Storage Account, container, RBAC, and
   optional RG lock (see main.tf). State lives in `./terraform.tfstate`.

    ```shell
    cd "$(git rev-parse --show-toplevel)/terraform/bootstrap-backend" || exit
    terraform init -upgrade || exit
    terraform validate || exit
    export TF_LOG='INFO'
    export TF_LOG_PATH='/tmp/terraform.log'
    # the following command may take a few minutes to run !!!
    terraform plan -out bootstrap.tfplan
    terraform apply bootstrap.tfplan
    ```

#### Pass 2 - Migrate state to Azure

1. Ensure you have created Terraform backend storage resources (e.g., resource
   group, storage account, and container) in Azure

   - resource group:

       ```shell
       az group list --output table
       ```

   - storage account:

       ```shell
       az storage account show \
       --name "${TF_VAR_storage_account_id}" \
       --resource-group "${TF_VAR_backend_resource_group_name}" \
       -o table
       ```

   - container:

       ```shell
       az storage container list \
       --account-name "${TF_VAR_storage_account_id}" \
       --auth-mode login \
       --output table
       ```

2. Re-enable [backend.tf](./backend.tf) by uncommenting the
   `terraform { backend "azurerm" {} }` block.

3. Ensure `bootstrap-backend/backend.tf` names the same three values you
   exported. Backend blocks accept no interpolation, so these are literals and
   must be edited by hand to match `TF_VAR_backend_resource_group_name`,
   `TF_VAR_storage_account_id` and `TF_VAR_container_name` — the committed file
   already carries the current values, and `envs/dev/backend.hcl` must agree
   with it:

   ```text
   terraform {
     backend "azurerm" {
       resource_group_name  = "rg-tfstate"
       storage_account_name = "sttfstaterubens01"
       container_name       = "tfstate"

       # IMPORTANT: this key is unique to the BOOTSTRAP state. Every module
       # root under envs/dev/ uses its own `<module>/terraform.tfstate` key
       # in the same container; two states sharing a key overwrite each other.
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

5. To tear the backend down again, follow [TF_BOOTSTRAP_DESTROY.md](TF_BOOTSTRAP_DESTROY.md).
   Do NOT run a bare `terraform destroy` here: once Pass 2 has completed, this
   module's own state lives in the container it manages, and destroying it
   in place deletes the storage account mid-apply and strands the state.
   `TF_BOOTSTRAP_DESTROY.md` migrates the state back to local first.

## Issue with Terraform local state in GitHub Actions

Terraform only manages what's recorded in its state file. If the state doesn't
contain the RG, Terraform assumes it doesn't exist and tries to create it. Azure
rejects that because it already exists, and Terraform tells you to import.

Seeing that error on a CI run means Terraform fell back to the LOCAL backend.
In GitHub Actions, runners are ephemeral, so unless the state is persisted,
each run starts with an empty state → destroy can't destroy anything and apply
tries to recreate existing resources, which then fails. This is exactly why
pipelines that use local state on ephemeral runners often fail on the second
run.

To fix the issue we need to import the existing resources (e.g., resource group,
storage account, and container name) into Terraform local state:

   ```bash
   terraform init -upgrade
   # import resource group
   terraform import azurerm_resource_group.tfstate \
      "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${TF_VAR_backend_resource_group_name}"
   # import storage account
   terraform import azurerm_storage_account.tfstate \
      "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${TF_VAR_backend_resource_group_name}/providers/Microsoft.Storage/storageAccounts/${TF_VAR_storage_account_id}"
   # import container name
   terraform import azurerm_storage_container.tfstate \
      "https://${TF_VAR_storage_account_id}.blob.core.windows.net/${TF_VAR_container_name}"
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
  version     = "5.4.0"
  constraints = "~> 5.4"
  hashes = [
    "h1:...",
    "zh:...",
    # ...
  ]
}
```

Each field means:

- `version` — the exact version Terraform picked on the last init, from the
  range allowed by `versions.tf`. The `5.4.0` shown above is illustrative;
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
   diff in the commit (`version = "5.4.0"` → `"5.5.0"`) instead of drifting
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
same commit as the `versions.tf` change, and record the version bump under
`[Unreleased]` in `CHANGELOG.md`.

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

Never destroy the backend while Terraform is still storing state in it —
deleting the storage account mid-apply strands the state file that describes
what is being deleted. The full procedure is in
[TF_BOOTSTRAP_DESTROY.md](TF_BOOTSTRAP_DESTROY.md); in outline it is:

- Destroy every other module in the estate first
- Comment out the `backend "azurerm"` block, returning this module to local
- `terraform init -migrate-state` to pull the state back to disk
- `terraform destroy`

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
