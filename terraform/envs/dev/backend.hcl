# -----------------------------------------------------------------------------
# terraform/envs/dev/backend.hcl
# -----------------------------------------------------------------------------
# Shared azurerm backend configuration used by every module root under
# envs/dev/<NN-module>/. Each module's backend.tf contains an EMPTY
# `terraform { backend "azurerm" {} }` block; the values below are supplied
# at init time:
#
#   terraform init \
#     -backend-config=../backend.hcl \
#     -backend-config="key=<module>/terraform.tfstate"
#
# Every module's state blob lives in this container under its own `key`.
# -----------------------------------------------------------------------------

# Resource group that owns the state storage account. Created (once) by the
# bootstrap-backend module. Do NOT change unless you re-bootstrap.
# ENSURE this value maps to TF_VAR_backend_resource_group_name
resource_group_name = "rg-tfstate"

# Globally-unique storage account holding the tfstate blob container. Also
# created by bootstrap-backend. Match the value that module wrote — if it
# drifts, `terraform init` fails with a "backend not found" error.
# ENSURE this value maps to TF_VAR_storage_account_id
storage_account_name = "sttfstaterubens01"

# Blob container inside the storage account. Every module's state blob lives
# here at path `<module>/terraform.tfstate` (the `key` supplied per module).
# ENSURE this value maps to TF_VAR_container_name
container_name = "tfstate"


# Authenticate to the storage data plane using the Service Principal supplied
# via ARM_* env vars (ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID,
# ARM_SUBSCRIPTION_ID). The backend fetches a storage account key at init
# time and uses it for blob I/O. Set to `true` only if the SP has
# `Storage Blob Data Contributor` (or equivalent) on the account — that role
# is granted in bootstrap-backend, so flipping this to `true` is possible
# once you're comfortable, but `false` keeps the existing bootstrap workflow.
use_azuread_auth = false
