# Provisioning the Terraform bootstrap backend

Steps to create `terraform/bootstrap-backend/` — the resource group, Storage
Account, blob container and RBAC assignment that hold the remote state for every
other module in this repo.

## Prerequisites

You must first complete the steps in [INITIAL_SETUP](../INITIAL_SETUP.md)

## There is no CI path, deliberately

The provisioning of the Terraform bootstrap backend must be hand-operated rather
than through an automated CICD workflow. That is because Terraform requires an
Azure storage account and blob container to store/read its state file there
remotely. And the CICD workflow, by design, only knows how to run
`terraform init/plan/apply` against a pre-configured Terraform backend.

## Terraform Resources Created

The following Terraform backend resources declared in
[main.tf](main.tf) are created.

| Address                                          | Named by                      | Note                                                             |
|--------------------------------------------------|-------------------------------|------------------------------------------------------------------|
| `azurerm_resource_group.tfstate`                 | `backend_resource_group_name` | Terraform resource group (TF_VAR_backend_resource_group_name)    |
| `azurerm_storage_account.tfstate`                | `storage_account_id`          | Globally-unique storage account name (TF_VAR_storage_account_id) |
| `azurerm_storage_container.tfstate`              | `container_name`              | Storage blob container (TF_VAR_container_name)                   |
| `azurerm_role_assignment.state_blob_contributor` | —                             | `Storage Blob Data Contributor`, scoped to the account           |

## Provisioning Steps

### Step 0 — Ensure Terraform Backend Is Not Available

Prior to provisioning the Terraform Bootstrap Backend resource group, ensure
that there is not one already created. If there is, you may not need to follow
the steps below.

- Check for an existing Terraform Bootstrap Backend resource group.

1. Sign in using the proper 'Service Principal' account
2. Check that there are no Terraform `tfstate` resource groups

    ```bash
    # sign in using service principal account
    az login --service-principal \
    --username "${AZURE_CLIENT_ID}" \
    --password "${AZURE_CLIENT_SECRET}" \
    --tenant "${AZURE_TENANT_ID}"
    # check for "${TF_VAR_backend_resource_group_name}" resource groups
    az group list \
    --query "[?name=='${TF_VAR_backend_resource_group_name}'].{Name:name, Location:location, State:properties.provisioningState}" \
    -o table
    ```

NOTE: if you see any resource groups listed above, STOP because you should 
already have the Terraform state backend resources already created.

### Step 1 — Initial Commands

1. Ensure the ARM_ and TF_VAR_ environment variables are set

    ```bash
    # ensure you have the ARM environment setup:
    env | grep '^ARM_'
    # ensure you have the TF_VAR environment setup:
    env | grep '^TF_VAR_'
    ```

2. Sign In as the Service Principal

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

3. Ensure Storage Account name is available

    ```bash
    az storage account check-name \
    --name "${TF_VAR_storage_account_id}" \
    --query nameAvailable -o tsv
    # should return true if account name is available.
    ```

4. Everything runs from this directory:

    ```bash
    cd "$(git rev-parse --show-toplevel)/terraform/bootstrap-backend"
    ```

### Step 2 — Comment out the backend block

Open [backend.tf](backend.tf) and comment out the entire
`terraform { backend "azurerm" { ... } }` block.

### Step 3 — Init and validate

- Initialize Terraform state

  ```bash
  terraform init -upgrade
  terraform validate
  ```

### Step 4 — Terraform Plan and Apply

- Terraform plan and display plan

  ```bash
  terraform plan -out=bootstrap.tfplan
  terraform show bootstrap.tfplan
  ```

- Terraform apply and verify resources created

    ```bash
    terraform apply bootstrap.tfplan
    # Verify resources created:
    terraform state list | grep -v '^data\.'
    az group show -n "${TF_VAR_backend_resource_group_name}" \
    --query location -o tsv
    az storage container list --account-name "${TF_VAR_storage_account_id}" \
    --auth-mode login -o table
    ```

### Step 5 — Restore the backend block

- Simply restore the original version

  ```bash
  git checkout -- backend.tf
  ```

### Step 6 — Migrate the Terraform state from local to Azure

- Migrate the Terraform state from the local `terraform.tfstate` file to the
  Azure Terraform storage blob container. The full destination is the blob
  `bootstrap/backend.tfstate` inside the Terraform backend blob container just
  provisioned.

  ```bash
  terraform init -migrate-state
  ```

### Step 7 — Terraform Plan to confirm "No Changes"

- Run Terraform plan, and expect "No Changes" as proof your infrastructure
  matches the Terraform configuration.

  ```bash
  terraform plan
  ```

### Step 8 — Clean up to leave the tree in a known state

- Delete the local artifacts that are now safe to remove — the state has moved
  to the blob, and the plan file is not portable.

    ```bash
    rm -f terraform.tfstate terraform.tfstate.backup bootstrap.tfplan
    ```

You are now done with the Terraform bootstrap. Every module root under
`terraform/envs/dev/` can now `init` against this backend.

---
Author:  [Rubens Gomes](https://rubensgomes.com/)
