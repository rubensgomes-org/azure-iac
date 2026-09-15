## Tearing Everything Down

The complete destroy of the entire project resources provisioned in Azure Cloud
involves 2 (two) phases:

1. Destroy the resources created by this project `terraform/roots/`
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

- Verify that all the `rg-${TF_VAR_workload}*-${TF_VAR_env}` resource groups are
  gone. Resource group names are `rg-<workload><purpose>-<env>`
  (see [NAMING.md](NAMING.md)), so the workload leads and the environment
  trails — anchor **both** ends, or a parallel estate in the same subscription
  is swept into the answer.

   ```bash
   az group list \
   --query "[?starts_with(name,'rg-${TF_VAR_workload}') && ends_with(name,'-${TF_VAR_env}')].{Name:name, Location:location, State:properties.provisioningState}" \
   -o table
   ```

### Purge Soft-Deleted Names Before Reprovisioning

**Do not skip this if you intend to stand the estate back up.** Names carry no
random suffix (see [NAMING.md](NAMING.md)), so a resource left in a soft-delete
recycle bin holds the one and only name the next `make apply` will ask for, and
the apply fails on it.

`make destroy` already checks and purges the Key Vault. The other two are
manual, and neither is reported by the teardown:

```bash
# Key Vault — 7-day retention here (soft_delete_retention_days in module 05).
# make destroy handles this; run it only if that step was skipped or failed.
az keyvault list-deleted \
  --query "[?name=='kv-${TF_VAR_workload}-${TF_VAR_env}'].name" -o tsv
az keyvault purge --name "kv-${TF_VAR_workload}-${TF_VAR_env}" \
  --location "${TF_VAR_location}"

# Log Analytics workspace — 14-day recycle bin, per resource group. Recreating
# with the same name inside the window either recovers the old workspace or
# fails outright. `--force` releases the name for a genuinely fresh one.
az monitor log-analytics workspace delete \
  --resource-group "rg-${TF_VAR_workload}observability-${TF_VAR_env}" \
  --workspace-name "log-${TF_VAR_workload}-${TF_VAR_env}" \
  --force --yes

# PostgreSQL Flexible Server — Azure retains a dropped server's name for up to
# 7 days. There is no `list-deleted` for this resource type, so the only
# signal is the apply failing on the name. The recovery counterpart is:
#   az postgres flexible-server revive-dropped ...
```

Storage account, Service Bus, ACR, Container App Environment and the
resource groups themselves release their names immediately on delete — nothing
to do for those.

### Destroying the Terraform Backend Resources

Follow the steps
in [TF_BOOTSTRAP_DESTROY.md](TF_BOOTSTRAP_DESTROY.md)

---
Author:  [Rubens Gomes](https://rubensgomes.com/)