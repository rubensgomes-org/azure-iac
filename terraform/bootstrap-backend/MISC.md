# Azure Storage Reference (background only)

**Do not follow these steps to provision anything.** Use
[TF_BOOTSTRAP_CREATE.md](TF_BOOTSTRAP_CREATE.md) to create the backend and
[TF_BOOTSTRAP_DESTROY.md](TF_BOOTSTRAP_DESTROY.md) to tear it down. The `az` commands below are
kept as background on what those Terraform configurations do underneath, and
on how to inspect the result by hand.

An Azure Storage Account is the top-level container for Azure storage services.
It provides a unique namespace and management boundary for storing data in
Azure. A storage account can contain blobs, files, queues, tables, and other
storage-related resources. Data stored in a storage account is designed to be
durable, highly available, secure, and scalable.

   ```text
   Subscription
     └── <resource group>
         └── <storage account>
             └── <container>
   ```

### Resource provider

1. Before creating the storage account, ENSURE the Microsoft.Storage Resource
   Provider is registered in your new Azure subscription.

    ```shell
    az provider register --namespace Microsoft.Storage
    ```

2. It should say "Registered":

    ```shell
    az provider show \
    --namespace Microsoft.Storage \
    --query registrationState -o tsv
    ```

### Resource group

1. Create a resource group for `Terraform`:

    ```shell
    # The names come from the environment set up in ../INITIAL_SETUP.md.
    # create Terraform resource group
    az group create \
    --name "${TF_VAR_backend_resource_group_name}" \
    --location centralus \
    --tags "owner=${TF_VAR_owner}"
    ```

2. List the resource groups:

    ```shell
    az group list --output table
    ```

3. Delete the resource group:

    ```shell
    az group delete \
    --name "${TF_VAR_backend_resource_group_name}" \
    --yes \
    --no-wait
    ```

### Storage account

1. Create the storage account for Terraform:

    ```shell
    # The storage account name must be globally unique across Azure.
    # The centralus is a good location/region for training and experimentation.
    az storage account create \
    --name "${TF_VAR_storage_account_id}" \
    --resource-group "${TF_VAR_backend_resource_group_name}" \
    --location centralus \
    --sku Standard_LRS
    ```

2. Check the storage account `kind` created:

    ```shell
    az storage account show \
    --name "${TF_VAR_storage_account_id}" \
    --resource-group "${TF_VAR_backend_resource_group_name}" \
    --query kind \
    -o tsv
    ```

3. Add "Storage Blob Data Contributor" role. `SP_OBJ_ID` is the Service
   Principal object ID captured in [INITIAL_SETUP.md](../INITIAL_SETUP.md):

    ```shell
    SCOPE="/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${TF_VAR_backend_resource_group_name}/providers/Microsoft.Storage/storageAccounts/${TF_VAR_storage_account_id}"
    az role assignment create \
      --assignee-object-id "${SP_OBJ_ID}" \
      --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Contributor" \
      --scope "${SCOPE}"
    ```

4. Delete the storage account:

    ```shell
    az storage account delete \
    --name "${TF_VAR_storage_account_id}" \
    --resource-group "${TF_VAR_backend_resource_group_name}"
    ```

### Blob container

Every command below uses `--auth-mode login`, which authenticates with the
signed-in principal's AAD token. This project does not use storage account
keys — the role assignment in step 8 is what makes these calls work.

1. List containers created under the storage account:

    ```shell
    az storage container list \
    --account-name "${TF_VAR_storage_account_id}" \
    --auth-mode login \
    --output table
    ```

2. Create the Blob Container to store the `Terraform` state:

   ```shell
   az storage container create \
   --name "${TF_VAR_container_name}" \
   --account-name "${TF_VAR_storage_account_id}" \
   --auth-mode login
   ```

3. Delete the Blob Container:

   ```shell
   az storage container delete \
   --name "${TF_VAR_container_name}" \
   --account-name "${TF_VAR_storage_account_id}" \
   --auth-mode login
   ```

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
