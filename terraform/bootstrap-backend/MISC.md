## General Instructions

FROM HERE ON, YOU SHOULD USE THE TERRAFORM CODE TO PROVISION
[TF_PROVISION](TF_PROVISION.md) OR TO DESTROY [TF_DESTROY](TF_DESTROY.md). THE
FOLLOWING STEPS ARE ONLY DISPLAYED FOR DOCUMENTATION PURSPOES ONLY:

1. Create a resource group for `Terraform`:

   ```shell
   # NOTE: It is recommended that you use Terraform commands from now on. 
   # Provide a good name for terraform resource group (e.g., rg-tfstate)
   TF_RESOURCE_GROUP='rg-tfstate'
   # create Terraform resource group
   az group create \
   --name "${TF_RESOURCE_GROUP}" \
   --location centralus \
   --tags owner=rubens.gomes
   ```

2. Create the storage account for Terraform:

   ```shell
   TF_RESOURCE_GROUP='rg-tfstate'
   # Provide a global unique name for the terraform storage account.
   TF_STORAGE_ACCOUNT='sttfstaterubens01'
   # The centralus is a good location/region for training and experimentation. 
   az storage account create \
   --name  "${TF_STORAGE_ACCOUNT}" \
   --resource-group "${TF_RESOURCE_GROUP}" \
   --location centralus \
   --sku Standard_LRS
   ```

3. Add "Storage Blob Data Contributor" role:

    ```shell
    SCOPE="/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${TF_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${TF_STORAGE_ACCOUNT}"
    az role assignment create \
      --assignee-object-id "${TF_OBJECT_ID}" \
      --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Contributor" \
      --scope "${SCOPE}"
    ```

4. Create a resource group for `Terraform`:

   ```shell
   # login from the browser / select subscription
   az login --tenant '<ARM_TENANT_ID>'
   TF_RESOURCE_GROUP='<SECRET>'
   # create Terraform resource group
   az group create \
   --name "${TF_RESOURCE_GROUP}" \
   --location centralus
   ```

5. List the resource groups:

    ```shell
    az group list --output table
    ```

6. Delete the resource group:

   ```shell
   az group delete \
   --name "${TF_RESOURCE_GROUP}" \
   --yes \
   --no-wait  
   ```

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

7. Before creating the storage account, ENSURE the Microsoft.Storage Resource
   Provider is registered in your new Azure subscription.

   ```shell
   az provider register --namespace Microsoft.Storage
   ```

8. It should say "Registered":

    ```shell
    az provider show \
    --namespace Microsoft.Storage \
    --query registrationState -o tsv
    ```

9. Now create the storage account for Terraform:

   ```shell
   TF_RESOURCE_GROUP='<SECRET>'
   TF_STORAGE_ACCOUNT='<SECRET>'
   az storage account create \
   --name  "${TF_STORAGE_ACCOUNT}" \
   --resource-group "${TF_RESOURCE_GROUP}" \
   --location centralus \
   --sku Standard_LRS
   ```

10. Check the storage account `kind` created:

    ```shell
    az storage account show \
    --name "${TF_STORAGE_ACCOUNT}" \
    --resource-group "${TF_RESOURCE_GROUP}" \
    --query kind \
    -o tsv
    ```

11. Delete the storage account:

    ```shell
    az storage account delete \
    --name "${TF_STORAGE_ACCOUNT}" \
    --resource-group "${TF_RESOURCE_GROUP}"
    ```

12.  Get Storage Account key:

    ```shell
    az storage account keys list \
    --resource-group "${TF_RESOURCE_GROUP}" \
    --account-name "${TF_STORAGE_ACCOUNT}" \
    --query "[0].value" \
    -o tsv
    # take note of output and store it in TF_STORAGE_KEY
    ```

13. List containers created under the storage account:

    ```shell
    az storage container list \
    --account-name "${TF_STORAGE_ACCOUNT}" \
    --account-key "${TF_STORAGE_KEY}" \
    --output table
    ```

14. Create the Blob Container to store the `Terraform` state:

    ```shell
    TF_CONTAINER='<SECRET>'
    az storage container create \
    --name "${TF_CONTAINER}" \
    --account-name "${TF_STORAGE_ACCOUNT}" \
    --account-key "${TF_STORAGE_KEY}"
    ```

15. Delete the Blob Container:

    ```shell
    TF_CONTAINER='<SECRET>'
    az storage container delete \
    --name "${TF_CONTAINER}" \
    --account-name "${TF_STORAGE_ACCOUNT}" \
    --account-key "${TF_STORAGE_KEY}"
    ````
