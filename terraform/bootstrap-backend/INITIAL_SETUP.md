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
   # login as a User from the browser / select subscription
   # You need to know your Azure Tenant ID below.
   az login --tenant "${ARM_TENANT_ID}"
   # Confirm the User as the type of login
   az account show --query user
   # You need to be the owner of the subscription below
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
    # Login as a User (NOT Service Principal)
    # login as a User from the browser / select subscription
    # You need to know your Azure Tenant ID below.
    az login --tenant "${ARM_TENANT_ID}"
    # display azure account info
    az account show
    ```

3. create service principal

   ```shell
   # Remember you should have Ownere RBAC role on this subscription
   ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   # name the SP username as you please (e.g., terraform-sp is a good one)
   TF_SERVICE_PRINCIPAL='terraform-sp'
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
   # The "appId" from previous `az ad sp create-for-rbac` outtput.
   APP_ID='<SECRET>' # from the previous command.
   # take note of the "TF_OBJECT_ID" displayed
   az ad sp show --id "${APP_ID}" --query id -o tsv
   ```

5. Add "User Access Administrator" role:

    ```shell
    az role assignment create \
      --assignee-object-id "${TF_OBJECT_ID}" \
      --assignee-principal-type ServicePrincipal \
      --role "User Access Administrator" \
      --scope "/subscriptions/${ARM_SUBSCRIPTION_ID}"
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
   # SP (Service Principal) username which is the same as appId output when the
   # 
   # ARM_CLIENT_ID is the value of "appId" output when the 
   # `az ad sp create-for-rbac` was run to create the SP.
   # ARM_CLIENT_SECRET is the value of "password" output when the 
   # `az ad sp create-for-rbac` was run to create the SP.
   # SP (Service Principal) username:
   ARM_CLIENT_ID='<SECRET>'
   # SP (Service Principal) password:
   ARM_CLIENT_SECRET='<SECRET>'
   # You must know your tenant ID
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

## Terraform Azure Resource Manager Environment Variables

1. take note of the following information:

    - appId:  ARM_CLIENT_ID/AZURE_CLIENT_ID
    - password: ARM_CLIENT_SECRET/AZURE_CLIENT_SECRET
    - tenant:  ARM_TENANT_ID/AZURE_TENANT_ID
    - subscription: ARM_SUBSCRIPTION_ID/AZURE_SUBSCRIPTION_ID 

2. Configure Azure Resource Manager (ARM) CLI Environment Variables

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
        ```

## GitHub Actions Secrets

The following variables are required by the GitHub Actions workflows:

   ```text
   # For example for the repo "azure-iac" 
   # Repo → Settings / Secrets and variables / Actions / (add secrets here) 
   AZURE_CLIENT_ID='<SECRET>'
   AZURE_CLIENT_SECRET='<SECRET>'
   AZURE_SUBSCRIPTION_ID='<SECRET>'
   AZURE_TENANT_ID='<SECRET>'
   ```


---
Author:  [Rubens Gomes](https://rubensgomes.com/)