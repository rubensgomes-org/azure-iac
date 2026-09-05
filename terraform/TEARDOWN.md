## Tearing Everything Down

The complete destroy of the entire project resources provisioned in Azure Cloud
involves 2 (two) phases:

1. Destroy the resources created by this project `terraform/envs/$(ENV)/`
   modules. This is actual infrastructure estate consumed by the applications in
   the cloud (e.g., networking, key vault, container apps, and database).
2. Destroy the Terraform bootstrap backend which are the resources (e.g.,
   resource group, storage account, and blob container) consumed by Terraform to
   maintain its State in Azure cloud.

### Prerequisites

Prior to running the steps in this file you must have the following requirements
satisfied:

- Go thru the [INITIAL_SETUP](INITIAL_SETUP.md) to make sure you have the basics
  setup:

1. The correct 'Service Principal' account provisioned with the right RBAC roles
   assigned to it.
2. The different Resource Providers registered with the Subscription associated
   with the 'Service Principal' account.
3. The "AZURE_*", "ARM_*", and "TF_VAR_*" environment variables properly defined
   and exported in your operating system shell environment.
4. Every module input exported as a `TF_VAR_*`, per "Terraform Environment"
   of the [INITIAL_SETUP](INITIAL_SETUP.md#terraform-environment) file. A
   destroy needs the same inputs an apply does.

### Destroying the Azure Cloud Estate

1. Ensure you have the `ARM_*` and `TF_VAR_*`environment variables defined.
2. Sign in as a "Service Principal" user
3. Change to the project root directory
4. Run `make destroy`. ! SEE WARNING BELOW !

WARNINGS:

- `make` destroy will traverse all the project modules and run
  `terraform destroy -auto-approve`. It will actually delete resource groups,
  networking, Key Vault, ACR, storage, Service Bus, PostgreSQL, container
  apps/environment, and monitoring in whatever Azure subscription your ARM_*
  /TF_VAR_* environment vars point to.

- It's irreversible for anything without soft-delete/purge protection (e.g., ACR
  images, storage blobs not under retention).

- If you're using this against a real/shared subscription rather than a
  disposable sandbox, this is destructive to actual provisioned infrastructure,
  not a dry run.

  ```bash
  az login --service-principal \
  --username "${AZURE_CLIENT_ID}" \
  --password "${AZURE_CLIENT_SECRET}" \
  --tenant "${AZURE_TENANT_ID}"
  cd "$(git rev-parse --show-toplevel)"
  # walks modules, sweeping Azure-generated orphans
  make destroy
  ```

### Verify Resources Are Gone

- Verify that all the "rg-dev-*${TF_VAR_rg_suffix}" resource groups are gone

   ```bash
   # check for "dev" resource groups
   az group list \
   --query "[?starts_with(name,'rg-dev-') && ends_with(name,'${TF_VAR_rg_suffix}')].{Name:name, Location:location, State:properties.provisioningState}" \
   -o table
   ```

### Destroying the Terraform Backend Resources

Follow the steps
in [TF_BOOTSTRAP_DESTROY.md](bootstrap-backend/TF_BOOTSTRAP_DESTROY.md)

---
Author:  [Rubens Gomes](https://rubensgomes.com/)