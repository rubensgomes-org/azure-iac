# Azure and Terraform SetUp

This file describes pre-requisite configuration steps required to allow
Terraform to authenticate and create resources in Microsoft Azure Cloud.

## Installing Azure CLI

You must have the Microsoft Azure CLI tool installed at your local machine. Here
is how it was installed in a macOS:

```shell
brew install azure-cli
```

## Installing Terraform

You must have the Hashcor Terraform CLI tool installed at your local machine. 
Here is how it was installed in a macOS:

```shell
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

## Microsoft Account and Azure Subscription

A Microsoft Account is required to sign up for an Azure Account. And a
Microsoft Azure Subscription is required to provision resources in Azure Cloud.

An Azure subscription is a container used to provision resources in Azure. It
holds the details of all your resources like virtual machines (VM), databases,
and more. When you create an Azure resource like a VM, you identify the
subscription it belongs to.

## Register Azure Resource Providers

Azure services are exposed through `Resource Providers` (RPs). And every Azure
service belongs to a provider namespace:

| Azure Service     |      Provider Namespace       |
|:------------------|:-----------------------------:|
| ACR               |  Microsoft.ContainerRegistry  |
| App Configuration |  Microsoft.AppConfiguration   |
| Container Apps    |         Microsoft.App         |
| Front Door        |         Microsoft.Cdn         |
| Key Vault         |      Microsoft.KeyVault       |
| Log Analytics     | Microsoft.OperationalInsights |
| PostgreSQL        |   Microsoft.DBforPostgreSQL   |
| Storage Accounts  |       Microsoft.Storage       |
| Virtual Machines  |       Microsoft.Compute       |
| Virtual Networks  |       Microsoft.Network       |

For example, the Azure Container Apps uses the `Microsoft.App` resource
provider. Therefore, the subscription must have that `Microsoft.App` RP
registered before Terraform can create an azurerm_container_app_environment. The
same applies to several other providers as well.

- Register several RPs you’ll certainly need for running `Terraform`.  
  Basically the following commands is telling Azure that the subscription
  intends to use the below providers when running `Terraform`

- The following establishes an Azure session using  `Login as a User`:

   ```shell
   # Login as a User (NOT Service Principal)
   az login --tenant '<ARM_TENANT_ID>'
   # Confirm the User as the type of login
   az account show --query user
   az account set --subscription "${ARM_SUBSCRIPTION_ID}"
   # ACR:
   az provider register --verbose --namespace Microsoft.ContainerRegistry
   # App Configuration:
   az provider register --verbose --namespace Microsoft.AppConfiguration
   # Container App:
   az provider register --verbose --namespace Microsoft.App
   # Front Door:
   az provider register --verbose --namespace Microsoft.Cdn
   # Key Vault:
   az provider register --verbose --namespace Microsoft.KeyVault
   # Log Analytics
   az provider register --verbose --namespace Microsoft.OperationalInsights
   # PostGres SQL Server
   az provider register --verbose --namespace Microsoft.DBforPostgreSQL
   # Storage Account:
   az provider register --verbose --namespace Microsoft.Storage
   # Virtual Machine:
   az provider register --verbose --namespace Microsoft.Compute
   # Virtual Network:
   az provider register --verbose --namespace Microsoft.Network
   ```

- To check the registration status with a given provider:

    ```shell
    # for example with the Azure Container Apps provider:
    az provider show --namespace Microsoft.App --query "registrationState" -o tsv
    ```

## `Terraform` Azure Service Principal and Secrets

We are using a `Service Principal + Secrets` to allow Terraform to authenticate
against Azure. Also, since Terraform is assigning roles to some resource, this
`Service Principal` must have the `User Access Administrator` role assigned to
it.

### Create Azure Service Principal

1. Login as a User to Azure from the browser
2. select the subscription at the CLI prompt

    ```shell
    # login as a User from the browser / select subscription
    az login --tenant '<ARM_TENANT_ID>'
    # display azure account info
    az account show
    ```

3. create service principal

   ```shell
   ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   TF_SERVICE_PRINCIPAL='<SECRET>'
   # take note of the following displayed output:
   # "appId" --> SP (Service Principal) username = ARM_CLIENT_ID
   # "password" --> SP (Service Principal) password = ARM_CLIENT_SECRET
   az ad sp create-for-rbac \
   --name ${TF_SERVICE_PRINCIPAL} \
   --role Contributor \
   --scopes "/subscriptions/${ARM_SUBSCRIPTION_ID}" \
   --verbose
   ```

4. Find the TF_OBJECT_ID

   ```shell
   APP_ID='<SECRET>' # from the previous command.
   # take note of the "TF_OBJECT_ID" displayed
   az ad sp show --id "${APP_ID}" --query id -o tsv
   ```

### Add Service Principal Roles

1. Add "User Access Administrator" role:

    ```shell
    az role assignment create \
      --assignee-object-id "${TF_OBJECT_ID}" \
      --assignee-principal-type ServicePrincipal \
      --role "User Access Administrator" \
      --scope "/subscriptions/${ARM_SUBSCRIPTION_ID}"
    ```

2. Create a resource group for `Terraform`:

   ```shell
   TF_RESOURCE_GROUP='<SECRET>'
   # create Terraform resource group
   # NOTE: I changed the location of the Terraform resource group from 
   # eastus to centralus
   az group create \
   --name "${TF_RESOURCE_GROUP}" \
   --location centralus
   ```

3. Create the storage account for Terraform:

   ```shell
   TF_RESOURCE_GROUP='<SECRET>'
   TF_STORAGE_ACCOUNT='<SECRET>'
   # NOTE: I changed the location of the Terraform resource group from 
   # eastus to centralus
   az storage account create \
   --name  "${TF_STORAGE_ACCOUNT}" \
   --resource-group "${TF_RESOURCE_GROUP}" \
   --location centralus \
   --sku Standard_LRS
   ```

4. Add "Storage Blob Data Contributor" role:

    ```shell
    SCOPE="/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${TF_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${TF_STORAGE_ACCOUNT}"
    az role assignment create \
      --assignee-object-id "${TF_OBJECT_ID}" \
      --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Contributor" \
      --scope "${SCOPE}"
    ```

### Verify Azure Service Principal Roles

1. Verify the Service Principal has the expected roles for the right scopes:

    ```shell
    SCOPE1="/subscriptions/${ARM_SUBSCRIPTION_ID}"
    az role assignment list \
      --assignee-object-id "${TF_OBJECT_ID}" \
      --scope "${SCOPE1}" \
      -o table
    SCOPE2="/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${TF_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${TF_STORAGE_ACCOUNT}"
    az role assignment list \
      --assignee-object-id "${TF_OBJECT_ID}" \
      --scope "${SCOPE2}" \
      -o table
    ```

2. Test Login using the service principal;

   ```shell
   az logout
   # SP (Service Principal) username:
   ARM_CLIENT_ID='<SECRET>'
   # SP (Service Principal) password:
   ARM_CLIENT_SECRET='<SECRET>'
   ARM_TENANT_ID='<SECRET>'
   az login --service-principal \
   --username "${ARM_CLIENT_ID}" \
   --password "${ARM_CLIENT_SECRET}" \
   --tenant "${ARM_TENANT_ID}" \
   --allow-no-subscriptions
   # Confirm the ServicePrincipal as the type of login
   az account show --query user
   # To display the ARM_CLIENT_ID/AZURE_CLIENT_ID
   az account show --query user.name -o tsv
   ```

## SetUp CLI Environment Variables

1. take note of the following secret information which are needed by
   `Terraform` and GitHub Action:

    - appId → ARM_CLIENT_ID/AZURE_CLIENT_ID
    - password → ARM_CLIENT_SECRET/AZURE_CLIENT_SECRET
    - tenant → ARM_TENANT_ID/AZURE_TENANT_ID

2. Display the Service Principal Object Id (ARM_OBJECT_ID):

   - A Client ID (ARM_CLIENT_ID/AZURE_CLIENT_ID) identifies the application
   - A Service Principal Object ID (TF_OBJECT_ID) identifies the actual Service 
     Principal instance in the tenant

     ```shell
     ARM_CLIENT_ID='<SECRET_INFO>'
     # displays the object id:
     az ad sp show --id "${ARM_CLIENT_ID}" --query id -o tsv
     # Take note of the output and store it in TF_OBJECT_ID
     ```

3. Configure Azure Resource Manager (ARM) CLI Environment Variables

    - The following environment variables are needed by `terraform`
      hashicorp/azurerm provider module at runtime:

        ```shell
        export ARM_CLIENT_ID='<SECRET>'
        export ARM_CLIENT_SECRET='<SECRET>'
        export ARM_SUBSCRIPTION_ID='<SECRET>'
        export ARM_SUBSCRIPTION_NAME='<SECRET>'
        export ARM_TENANT_ID='<SECRET>'
        export TF_OBJECT_ID='<SECRET>'
        export TF_LOG='INFO'
        export TF_LOG_PATH='/tmp/terraform.log'
        # the following are not known at this time yet.  These variables are 
        # defined as part of the bootstrap-backend module which should be done 
        # prior to anything else.
        # export TF_CONTAINER='<SECRET>'
        # export TF_RESOURCE_GROUP='<SECRET>'
        # export TF_STORAGE_ACCOUNT='<SECRET>'
        # export TF_STORAGE_KEY='<SECRET>'
        ```

## GitHub Actions Environment Variables

The following variables are required by GitHub Actions workflows

1. Save the credentials to the corresponding GitHub repo:

   ```text
   "azure-iac" Repo → Settings → Environments → AZURE → Environment secrets 
   AZURE_CLIENT_ID='<SECRET>'
   AZURE_CLIENT_SECRET='<SECRET>'
   AZURE_SUBSCRIPTION_ID='<SECRET>'
   AZURE_TENANT_ID='<SECRET>'
   ```

## Bootstrap Terraform Backend Resources

_You should now proceed to create the Terraform resource group. storage 
account and Blob Container as described in the [README](./bootstrap-backend/README.md)_

## `Terraform` Azure Resource Group -- DO NOT RUN THIS USING AZ CLI

**NOTE: TO BE DONE BY TERRAFORM !!!  THE CREATION OF ANY RESOURCES IN AZURE
MUST BE DONE USING TERRAFORM TO AUTOMATE THE CREATION/DESTROY OF THOSE
RESOURCES AS NEEDED.**

Resource groups provide a logical container to manage and organize Azure
resources, simplifying administration and enabling efficient resource
management.

- Create a resource group for `Terraform`:

   ```shell
   # login from the browser / select subscription
   az login --tenant '<ARM_TENANT_ID>'
   TF_RESOURCE_GROUP='<SECRET>'
   # create Terraform resource group
   az group create \
   --name "${TF_RESOURCE_GROUP}" \
   --location centralus
   ```

- List the resource groups:

    ```shell
    az group list --output table
    ```

- Delete the resource group:

    ```shell
    az group delete \
    --name "${TF_RESOURCE_GROUP}" \
    --yes \
    --no-wait  
    ```

## `Terraform` Azure Storage Account -- DO NOT RUN THIS USING AZ CLI

**NOTE: TO BE DONE BY TERRAFORM !!!  THE CREATION OF ANY RESOURCES IN AZURE
MUST BE DONE USING TERRAFORM TO AUTOMATE THE CREATION/DESTROY OF THOSE
RESOURCES AS NEEDED.**

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

- Before creating the storage account, ENSURE the Microsoft.Storage Resource
  Provider is registered in your new Azure subscription.

   ```shell
   az provider register --namespace Microsoft.Storage
   ```

- It should say "Registered":

    ```shell
    az provider show \
    --namespace Microsoft.Storage \
    --query registrationState -o tsv
    ```

- Now create the storage account for Terraform:

   ```shell
   TF_RESOURCE_GROUP='<SECRET>'
   TF_STORAGE_ACCOUNT='<SECRET>'
   az storage account create \
   --name  "${TF_STORAGE_ACCOUNT}" \
   --resource-group "${TF_RESOURCE_GROUP}" \
   --location centralus \
   --sku Standard_LRS
   ```

- Check the storage account `kind` created:

    ```shell
    az storage account show \
    --name "${TF_STORAGE_ACCOUNT}" \
    --resource-group "${TF_RESOURCE_GROUP}" \
    --query kind \
    -o tsv
    ```

- Delete the storage account:

    ```shell
    az storage account delete \
    --name "${TF_STORAGE_ACCOUNT}" \
    --resource-group "${TF_RESOURCE_GROUP}"
    ```

## `Terraform` Azure Blob Container -- DO NOT RUN THIS USING AZ CLI

**NOTE: TO BE DONE BY TERRAFORM !!!  THE CREATION OF ANY RESOURCES IN AZURE
MUST BE DONE USING TERRAFORM TO AUTOMATE THE CREATION/DESTROY OF THOSE
RESOURCES AS NEEDED.**

- Get Storage Account key:

    ```shell
    az storage account keys list \
    --resource-group "${TF_RESOURCE_GROUP}" \
    --account-name "${TF_STORAGE_ACCOUNT}" \
    --query "[0].value" \
    -o tsv
    # take note of output and store it in TF_STORAGE_KEY
    ```

- List containers created under the storage account:

    ```shell
    az storage container list \
    --account-name "${TF_STORAGE_ACCOUNT}" \
    --account-key "${TF_STORAGE_KEY}" \
    --output table
    ```

- Create the Blob Container to store the `Terraform` state:

    ```shell
    TF_CONTAINER='<SECRET>'
    az storage container create \
    --name "${TF_CONTAINER}" \
    --account-name "${TF_STORAGE_ACCOUNT}" \
    --account-key "${TF_STORAGE_KEY}"
    ```

- Delete the Blob Container:

    ```shell
    TF_CONTAINER='<SECRET>'
    az storage container delete \
    --name "${TF_CONTAINER}" \
    --account-name "${TF_STORAGE_ACCOUNT}" \
    --account-key "${TF_STORAGE_KEY}"
    ````

---
Author:  [Rubens Gomes](https://rubensgomes.com/)