# Destroying the Terraform Backend Bootstrap State

This file documents the steps to tear down the `Terraform Bootstrap Backend`
configuration in Azure cloud. It provides steps to properly delete the Terraform
Resource Group, Storage Account, blob container used by Terraform in Azure.

## Important Considerations

Two things to know before starting:

1. All the Azure resources (`terraform/envs/$(ENV)/`  
   modules) provisioned and maintained by this Terraform project must be
   properly removed prior to destroying the Terraform bootstrap backend
   resources below.

2. Deleting the Terraform Storage Account deletes every `Terraform` module state
   blob inside it, along with the versioning and soft-delete policies that would
   otherwise protect them. There is no purge or restore step.

## Terraform Resources Destroyed

The following Terraform backend resources declared in
[main.tf](main.tf) are deleted.

| Address                                          | Named by                      | Note                                                             |
|--------------------------------------------------|-------------------------------|------------------------------------------------------------------|
| `azurerm_resource_group.tfstate`                 | `backend_resource_group_name` | Terraform resource group (TF_VAR_backend_resource_group_name)    |
| `azurerm_storage_account.tfstate`                | `storage_account_id`          | Globally-unique storage account name (TF_VAR_storage_account_id) |
| `azurerm_storage_container.tfstate`              | `container_name`              | Storage blob container  (TF_VAR_container_name)                  |
| `azurerm_role_assignment.state_blob_contributor` | —                             | `Storage Blob Data Contributor`, scoped to the account           |

## Steps to destroy the Terraform backend resources

### Step 0 — Ensure Azure Estate Is Cleared

Prior to destroying the Terraform Bootstrap Backend, we must ensure that the
Azure Cloud infrastructure estate maintained by this project is completely
destroyed.

1. Sign in using the proper 'Service Principal' account
2. Check all the `terraform/modules` resource groups are gone

   ```bash
   # sign in using service principal account
   az login --service-principal \
   --username "${AZURE_CLIENT_ID}" \
   --password "${AZURE_CLIENT_SECRET}" \
   --tenant "${AZURE_TENANT_ID}"
   # check for "dev" resource groups
   az group list \
   --query "[?starts_with(name,'rg-dev-') && ends_with(name,'${TF_VAR_rg_suffix}')].{Name:name, Location:location, State:properties.provisioningState}" \
   -o table
   ```

NOTE: if you see any resource groups listed above, STOP and clean up those 
resources first prior to continuing.

### Step 1 — Initial Commands

The following commands ensure you have the right start.

1. Ensure you are in the right Terraform bootstrap folder.

    ```bash
    # Everything runs from this directory:
    cd "$(git rev-parse --show-toplevel)/terraform/bootstrap-backend"
    ```

2. Ensure you are signed in using the proper 'Service Principal' account.

    ```bash
    # Ensure you are not currently signed in already.
    az logout
    az login --service-principal \
    --username "${AZURE_CLIENT_ID}" \
    --password "${AZURE_CLIENT_SECRET}" \
    --tenant "${AZURE_TENANT_ID}"
    # Confirm the ServicePrincipal as the type of login
    az account show --query user
    # To display the AZURE_CLIENT_ID
    az account show --query user.name -o tsv
    ```

3. Run `terraform init` to install required hashicorp terraform plugins, and
   reconfigure the Terraform bootstrap backend to the correct values.

    ```bash
    terraform init -reconfigure \
    -backend-config="resource_group_name=${TF_VAR_backend_resource_group_name}" \
    -backend-config="storage_account_name=${TF_VAR_storage_account_id}" \
    -backend-config="container_name=${TF_VAR_container_name}"
    ```

4. The following information must be correctly configured in the corresponding
   files and environment variables:

   All three values below must agree across `bootstrap-backend/backend.tf` and
   `envs/dev/backend.hcl`:

   | Information         | Environment Variable               |
   |---------------------|------------------------------------|
   | resource group name | TF_VAR_backend_resource_group_name |
   | storage account     | TF_VAR_storage_account_id          |
   | container name      | TF_VAR_container_name              |

   The state `key` is a literal in `bootstrap-backend/backend.tf` only — it has
   no environment variable and is not overridden by the `-backend-config` flags
   in step 3.

### Step 2 — List the Terraform State

- NOTE: If there is no result from the following command, your Terraform state
  in the Azure storage container blob is empty.

    ```bash
    terraform state list | grep -v '^data\.'
    # see NOTE above when nothing is returned.
    ```

**If the state is empty, skip ahead to Step 8.** Steps 3 to 7 migrate and
destroy state that is not there. Steps 8 and 9 still apply: the Azure resources
can outlive the state that tracked them.

### Step 3 — Comment Out the Backend Block

Open [backend.tf](backend.tf) and comment out the entire
`terraform { backend "azurerm" { ... } }` block.

### Step 4 — Pull State Down to a Local File

```bash
cd "$(git rev-parse --show-toplevel)/terraform/bootstrap-backend"
terraform init -migrate-state
```

Answer `yes` at the prompt. Terraform detects the backend change and copies the
blob's contents into `./terraform.tfstate`.

Do NOT delete `.terraform/` first. `terraform init -migrate-state` reads
`.terraform/terraform.tfstate` to learn which backend the state is currently in;
without it Terraform initializes a fresh local backend and migrates nothing,
which is the opposite of this step's purpose.

**Verify the migration actually moved something before going further** — this is
the last point at which a mistake is still cheap:

```bash
terraform state list
ls -l terraform.tfstate
# Also confirm the local backend took effect:
cat .terraform/terraform.tfstate
# local backend   → {"version": 3, "terraform_version": "..."}  (no "backend" key)
# azurerm backend → a "backend" object naming the storage account
```

### Step 5 — Plan the Destroy and Read It

```bash
terraform plan -destroy -out=destroy.tfplan \
  -var backend_resource_group_name="${TF_VAR_backend_resource_group_name}" \
  -var storage_account_id="${TF_VAR_storage_account_id}"
terraform show destroy.tfplan
```

### Step 6 — Destroy the Terraform State

```bash
terraform apply destroy.tfplan
```

### Step 7 — Verify Terraform State Is Empty

```bash
# Terraform's view: no managed resources left.
terraform state list | grep -v '^data\.'                    # → no output
# Azure's view: the backend's own resources are gone.
az group exists -n "${TF_VAR_backend_resource_group_name}"   # → false
az storage account show -n "${TF_VAR_storage_account_id}"    # → ResourceNotFound
```

A successful destroy in step 6 leaves nothing for steps 8 and 9 to do. They
exist for the case step 2 sent you here directly — the state was empty, so
Terraform never knew about resources that are still standing in Azure. Both
commands below are safe to run either way.

### Step 8 — Destroy the Terraform Storage Account

1. Check if there is a Terraform storage account.
2. If there is one, go ahead and destroy it.

    ```bash
    # Check if there is a Terraform backend storage account
    az storage account show -n "${TF_VAR_storage_account_id}"
    az storage account delete \
    --name "${TF_VAR_storage_account_id}" \
    --resource-group "${TF_VAR_backend_resource_group_name}" \
    --yes
    ```

### Step 9 — Destroy the Terraform Resource Group

1. Check if there is a Terraform resource group.
2. If there is one, go ahead and destroy it.

    ```bash
    # Check if there is a Terraform backend resource group
    az group exists -n "${TF_VAR_backend_resource_group_name}"
    az group delete --name "${TF_VAR_backend_resource_group_name}" --yes
    ```

### Step 10 — Leave the Tree in a Known State

1. Restore the [backend.tf](backend.tf) so the committed tree matches what a
   fresh clone should look like
2. Delete the local state artifacts. They describe resources that no longer
   exist. A stale `terraform.tfstate` makes a later `apply` try to recreate.

    ```bash
    git checkout -- backend.tf
    rm -f terraform.tfstate terraform.tfstate.backup destroy.tfplan
    ```

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
