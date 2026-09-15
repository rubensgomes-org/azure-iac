# -----------------------------------------------------------------------------
# terraform/envs/lab/backend.hcl
# -----------------------------------------------------------------------------
# Shared azurerm backend configuration for the `lab` environment. Every module
# root under terraform/roots/ contains an EMPTY `terraform { backend "azurerm"
# {} }` block; the values below are supplied at init time:
#
#   terraform init \
#     -backend-config=../../envs/lab/backend.hcl \
#     -backend-config="key=<module>/terraform.tfstate"
#
# The roots are shared by every environment. What makes a run "lab" rather than
# "dev" is this file plus `TF_VAR_env=lab` -- nothing in the HCL names either.
# -----------------------------------------------------------------------------

# Resource group and storage account are DELIBERATELY the same as dev's.
#
# The backend is subscription-level shared infrastructure: bootstrap-backend's
# own variables.tf says it "outlives and spans every environment". Environments
# are separated one level down, by container.
#
# The `-lab` in the RG name is therefore a naming concession and NOT a scoping
# one -- a `dev` estate's state blobs live in a container inside this
# lab-named group. Read the name as the workload's state store, not as lab's.
# ENSURE this value maps to TF_VAR_backend_resource_group_name
resource_group_name = "rg-rgomestfstate-lab"

# ENSURE this value maps to TF_VAR_storage_account_id
storage_account_name = "strgomestfstate02"

# The container is the ONLY per-environment backend coordinate, and it is what
# keeps lab's twelve state blobs apart from dev's. Both use the same keys
# (`<module>/terraform.tfstate`), so sharing a container would mean sharing
# state.
#
# The convention is `<workload>-<env>-tfstate`. A future `dev` gets
# `rgomes-dev-tfstate`, created out of band at that point.
#
# `bootstrap/backend.tfstate` also lives in here, and stays. The backend's own
# state spans every environment, so it is not lab's to move; it simply predates
# the per-environment split and shares the container. Worth knowing before
# anyone deletes a container thinking it holds only one environment.
#
# Creating a further container is done out of band, NOT by extending
# bootstrap-backend, which provisions exactly one from a single
# `azurerm_storage_container.tfstate` resource. Converting that to `for_each`
# changes its address, and without a `terraform state mv` first the apply
# would DESTROY the container holding every state blob:
#
#   az storage container create \
#     --account-name strgomestfstate02 \
#     --name rgomes-dev-tfstate \
#     --auth-mode login
#
# ENSURE this value maps to TF_VAR_container_name -- `make check-backend`
# fails the run if they disagree, because the environment variable OUTRANKS
# this file at init time (Makefile BACKEND_OVERRIDES).
container_name = "rgomes-lab-tfstate"

# Authenticate to the storage data plane using the Service Principal supplied
# via ARM_* env vars. Kept at `false` to match dev: the backend fetches a
# storage account key at init time and uses it for blob I/O. Flipping this to
# `true` needs `Storage Blob Data Contributor` on the account, which
# bootstrap-backend already grants.
use_azuread_auth = false
