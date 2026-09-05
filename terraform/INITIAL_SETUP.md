# Azure and Terraform Setup

This file describes pre-requisite configuration steps required to allow
Terraform to authenticate and create resources in Microsoft Azure Cloud.

## Tools Installation

- You must have the Microsoft Azure CLI tool (2.60+) installed on your local
  machine. Here is how it was installed on macOS:

    ```bash
    brew install azure-cli
    ```

- You must have the HashiCorp Terraform CLI tool (1.15+) installed on your
  local machine. Here is how it was installed on macOS:

    ```bash
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
    ```

## Microsoft Account and Azure Subscription

A Microsoft Account and an "Owner" Subscription are required to provision
resources in Azure Cloud. You should know your AZURE_TENANT_ID and "Owner"
AZURE_SUBSCRIPTION_ID.

- Below are the steps to sign in to Azure using your browser.

    ```bash
    # Login as a User (NOT Service Principal) from the browser, and make sure
    # you select a subscription with an "Owner" RBAC role.
    # You need to know your Azure Tenant ID below.
    az login --tenant "${AZURE_TENANT_ID}"
    # Confirm the User as the type of login
    az account show --query user
    # You need to be the owner of the subscription below
    az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
    ```

## Register Azure Resource Providers

The Azure Services and corresponding Provider Namespaces below are being
provisioned in this project.

| Azure Service      |      Provider Namespace       | Provisioned by |
|:-------------------|:-----------------------------:|:---------------|
| ACR                |  Microsoft.ContainerRegistry  | 06             |
| Container Apps     |         Microsoft.App         | 10, 11         |
| Key Vault          |      Microsoft.KeyVault       | 05             |
| Log Analytics      | Microsoft.OperationalInsights | 03             |
| Managed Identities |   Microsoft.ManagedIdentity   | 04             |
| Monitor            |      Microsoft.Insights       | 12             |
| PostgreSQL         |   Microsoft.DBforPostgreSQL   | 09             |
| Service Bus        |     Microsoft.ServiceBus      | 08             |
| Storage Accounts   |       Microsoft.Storage       | 07             |
| Virtual Networks   |       Microsoft.Network       | 02             |

The above "Resource Providers" must be registered with the Subscription to be
able to provision their corresponding resources in Azure cloud.

- Register the resource providers with the subscription. These commands tell
  Azure that the subscription intends to use the providers below when running
  `Terraform`:

    ```bash
    az login --tenant "${AZURE_TENANT_ID}"
    az account show --query user
    # ensure you are using an "Owner" subscription
    az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
    # ACR:
    az provider register --verbose --namespace Microsoft.ContainerRegistry
    # Container Apps + Container App Environment:
    az provider register --verbose --namespace Microsoft.App
    # Key Vault:
    az provider register --verbose --namespace Microsoft.KeyVault
    # Log Analytics:
    az provider register --verbose --namespace Microsoft.OperationalInsights
    # User-assigned managed identities:
    az provider register --verbose --namespace Microsoft.ManagedIdentity
    # App Insights, action groups, diagnostic settings:
    az provider register --verbose --namespace Microsoft.Insights
    # PostgreSQL:
    az provider register --verbose --namespace Microsoft.DBforPostgreSQL
    # Service Bus:
    az provider register --verbose --namespace Microsoft.ServiceBus
    # Storage Account:
    az provider register --verbose --namespace Microsoft.Storage
    # Virtual Network, NSGs, private DNS:
    az provider register --verbose --namespace Microsoft.Network
    ```

- To check your current subscription registration status with a given provider:

    ```bash
    # for example with the Azure Container Apps provider:
    az provider show --namespace Microsoft.App --query "registrationState" -o tsv
    ```

- Take note of your current Subscription Name (SUB_NAME)

    ```bash
    az account show --query name --output tsv
    # save the following in your environment:
    # SUB_NAME="<value of output>"
    ```

## `Terraform` Azure Service Principal and Secrets

We are using a `Service Principal + Service Principal Secret` to allow Terraform
to authenticate against Azure. The Service Principal needs TWO roles at
subscription scope, and neither is sufficient on its own:

- `Contributor` — creates, updates and deletes the resources themselves.
- `User Access Administrator` — creates the RBAC role assignments this project
  hands to the shared managed identity (`AcrPull`, `Key Vault Secrets User`,
  `Storage Blob Data Contributor`, the two Service Bus data roles).

`Owner` covers both and is a valid alternative on a personal subscription.

### Create Azure Service Principal

1. Login as a User to Azure from the browser
2. Select an "Owner" subscription
3. Create service principal
4. Take note of appId (AZURE_CLIENT_ID)
5. Take note of password (AZURE_CLIENT_SECRET)

    ```bash
    az login --tenant "${AZURE_TENANT_ID}"
    az account show --query user
    # ensure you are using an "Owner" subscription
    az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
    # name the SP username as you please (e.g., terraform-sp)
    SP_NAME='terraform-sp'
    # After running the command below take note of the following outputs:
    # "appId" --> SP (Service Principal) username = AZURE_CLIENT_ID
    # "password" --> SP (Service Principal) password = AZURE_CLIENT_SECRET
    # This creates the SP with Contributor. User Access Administrator is added
    # in step 7 -- Contributor alone cannot create role assignments, and
    # User Access Administrator alone cannot create resources.
    az ad sp create-for-rbac \
      --name "${SP_NAME}" \
      --role 'Contributor' \
      --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}" \
      --verbose
    # save the following in your environment:
    # AZURE_CLIENT_ID="<value of appId>"
    # AZURE_CLIENT_SECRET="<value of password>"
    ```

6. Find the Service Principal Object ID (SP_OBJ_ID)

    ```bash
    # take note of the "SP_OBJ_ID" displayed
    az ad sp show --id "${AZURE_CLIENT_ID}" --query id -o tsv
    # save the following in your environment:
    # SP_OBJ_ID="<value of output>"
    ```

7. Add the second role. Step 5 granted `Contributor`; this adds
   `User Access Administrator` so Terraform can create role assignments:

    ```bash
    az role assignment create \
      --assignee-object-id "${SP_OBJ_ID}" \
      --assignee-principal-type ServicePrincipal \
      --role "User Access Administrator" \
      --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}"
    ```

8. Test signing in using the Service Principal credentials:

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
    # The SP must see the subscription -- this prints its ID, not an error.
    az account show --query id -o tsv
    ```

### Verify Azure Service Principal Roles

- Verify the Service Principal holds BOTH roles for its Subscription ID
  (`Contributor` and `User Access Administrator`):

    ```bash
    SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}"
    az role assignment list \
      --assignee-object-id "${SP_OBJ_ID}" \
      --scope "${SCOPE}" \
      -o table
    ```

## Terraform Environment

You must have the variables below defined in your shell environment prior to 
running the `make` commands in this project.  Adjust the values of those 
variables accordingly.

### Terraform Azure Resource Manager Environment Variables

- Configure the following Terraform ARM_ shell environment variables:

    ```bash
    # ---------- >>> Azure <<< ----------
    export ARM_CLIENT_ID="${AZURE_CLIENT_ID}"
    export ARM_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"
    export ARM_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
    export ARM_TENANT_ID="${AZURE_TENANT_ID}"
    ```

### Terraform Azure Settings Environment Variables

- Configure the following Terraform settings shell environment variables:

  ```bash
  # ---------- >>> Terraform <<< ----------
  # TRACE|DEBUG|INFO|WARN|ERROR. INFO is the useful default; DEBUG is very
  # noisy. TF_LOG_PATH is a FILE path -- its parent directory must exist.
  export TF_LOG='INFO'
  export TF_LOG_PATH='/tmp/terraform.log'
  ```

### Terraform (tfvars) Environment Variables

- Configure the following Terraform (tfvars) shell environment variables:

    ```bash
    # ---------- >>> Terraform (tfvars) <<< ----------
    export TF_VAR_env='dev'
    export TF_VAR_location='centralus'
    export TF_VAR_prefix='rubens'
    export TF_VAR_action_group_email='rubens.s.gomes@gmail.com'
    export TF_VAR_pg_entra_admin_group_name='az-dev-pg-admins'
    export TF_VAR_pg_entra_admin_group_object_id='<object ID of the Entra group>'
    export TF_VAR_apps='["api","worker"]'

    export TF_VAR_acr_name='rubensdevacr'
    export TF_VAR_owner='rubens.s.gomes@gmail.com'

    # rg_suffix is deliberately LEFT UNSET. Empty means "no suffix", which is
    # this estate's normal naming (rg-dev-platform, rg-dev-network, ...).
    # Export it only to stand up a second, parallel estate -- `name` is
    # ForceNew on azurerm_resource_group, so setting it against a live estate
    # destroys and recreates all five RGs.
    #export TF_VAR_rg_suffix=''

    # The bootstrap-backend module locks rg-tfstate by default. This estate
    # runs it unlocked so a teardown does not have to remove the lock first.
    export TF_VAR_enable_rg_lock='false'

    export TF_VAR_backend_resource_group_name='rg-tfstate'
    export TF_VAR_container_name='tfstate'
    export TF_VAR_storage_account_id='sttfstaterubens01'
    ```

### Miscellaneous Environment Variables

- Configure the following miscellaneous shell environment variables:

    ```bash
    # ---------- >>> Miscellaneous <<< ----------
    # Variables previously determined in this file
    export SP_NAME='<value of Service Principal Name>'
    export SP_OBJ_ID='<value of Service Principal Object ID>'
    export SUB_NAME='<value of the Subscription Name>'
    ```

### Confirm

- `terraform` names any input it still lacks, so the check is simply to plan:

  ```bash
  cd "$(git rev-parse --show-toplevel)"
  make plan-resource-groups
  make plan-networking
  make plan-log-analytics
  make plan-managed-identities
  make plan-key-vault
  make plan-acr
  make plan-storage
  ```

A missing value fails with `No value for required variable`, naming it. If a
plan instead ignores a value you just exported, look for a leftover
`env.tfvars` or `terraform.tfvars` outranking it:

```bash
ls terraform/envs/dev/env.tfvars terraform/envs/dev/[0-9][0-9]-*/terraform.tfvars 2>/dev/null
```

## GitHub Actions Secrets and Variables

- Project Repository Action Variables:

    ```text
    # Repo → Settings / Secrets and variables / Actions / Variables
    AZURE_CLIENT_ID
    AZURE_SUBSCRIPTION_ID
    AZURE_TENANT_ID
    TF_VAR_BACKEND_RESOURCE_GROUP_NAME
    TF_VAR_STORAGE_ACCOUNT_ID
    TF_VAR_CONTAINER_NAME
    TF_VAR_LOCATION
    TF_VAR_OWNER
    # Do not add if you want the resource group name suffix empty.
    TF_VAR_RG_SUFFIX
    ```

- Project Repository Action Secrets:

    ```text
    # Repo → Settings / Secrets and variables / Actions / Secrets
    AZURE_CLIENT_SECRET
    ```

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
