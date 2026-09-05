# bootstrap-backend/backend.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Configures the remote state backend for the "bootstrap-backend" module
# itself. After this module has created the state Storage Account and
# container (see main.tf), its own state file is stored inside the very
# container it just provisioned.
#
# -----------------------------------------------------------------------------
# Chicken-and-egg workflow
# -----------------------------------------------------------------------------
# You cannot store state in a blob container that does not exist yet, so this
# module must be applied in TWO passes:
#
#   Pass 1 - Local state:
#     * Comment out (or remove) this entire `terraform { backend "azurerm" {} }`
#       block, OR run `terraform init` before the storage resources exist so
#       that Terraform falls back to the local backend.
#     * `terraform apply` creates the RG, Storage Account, container, RBAC,
#       and optional RG lock (see main.tf). State lives in
#       `./terraform.tfstate`.
#
#   Pass 2 - Migrate state to Azure:
#     * Re-enable this file (or leave it as-is on the first fresh clone).
#     * Run `terraform init -migrate-state`. Terraform detects the backend
#       change and prompts to copy the local state into the new blob.
#     * From then on, every plan/apply reads and writes to the blob.
#
# The README in this directory has the exact command sequence, including how
# to `terraform import` existing resources if a CI runner starts with an
# empty local state.
#
# -----------------------------------------------------------------------------
# Teardown safety
# -----------------------------------------------------------------------------
# NEVER `terraform destroy` this module while its state is stored in the very
# blob container it manages. Doing so deletes the Storage Account mid-apply
# and leaves the state file unreachable. Before destroying:
#   1. Switch this backend back to `local` (or remove the block).
#   2. `terraform init -migrate-state` to pull state back to disk.
#   3. `terraform destroy`.
# -----------------------------------------------------------------------------

terraform {
  # ---------------------------------------------------------------------------
  # AzureRM remote state backend
  # ---------------------------------------------------------------------------
  # The `azurerm` backend stores the Terraform state as a blob in an Azure
  # Storage Account. It supports state locking natively (via a blob lease on
  # the state blob), so concurrent `apply` runs on the same key are safely
  # serialised.
  #
  # NOTE: Backend blocks do NOT accept interpolations (`var.*`, `local.*`,
  # etc.). Values must be literals or supplied at init time via
  # `-backend-config=key=value` / `-backend-config=file.hcl`. The literals
  # below therefore must be kept in sync with this module's `terraform.tfvars`
  # (gitignored) and with `envs/dev/backend.hcl`.
  backend "azurerm" {
    # -------------------------------------------------------------------------
    # Backend storage location
    # -------------------------------------------------------------------------
    # Must match the resources created in main.tf:
    #   - resource_group_name  = var.backend_resource_group_name
    #   - storage_account_name = var.storage_account_id
    #   - container_name       = var.container_name
    # If you change any of those variable values (they come from `TF_VAR_*`;
    # see terraform/INITIAL_SETUP.md), update the literals here to match.

    # ENSURE this value maps to TF_VAR_backend_resource_group_name
    resource_group_name = "rg-tfstate"

    # ENSURE this value maps to TF_VAR_storage_account_id
    storage_account_name = "sttfstaterubens01"

    # ENSURE this value maps to TF_VAR_container_name
    container_name = "tfstate"

    # -------------------------------------------------------------------------
    # State blob key (path within the container)
    # -------------------------------------------------------------------------
    # `key` is the filename of the state blob inside `container_name`. Each
    # Terraform module in this repo MUST use a distinct key; two modules
    # sharing a key would overwrite each other's state on apply.
    #
    # Convention used here:  <module-name>/<state-file>.tfstate
    # Every module root under envs/dev/ supplies its own key at init time via
    # -backend-config="key=<module>/terraform.tfstate", for example:
    #   - networking/terraform.tfstate
    #   - postgresql/terraform.tfstate
    key = "bootstrap/backend.tfstate"

    # -------------------------------------------------------------------------
    # Authentication mode
    # -------------------------------------------------------------------------
    # `use_azuread_auth = false` tells the backend to authenticate to the
    # Storage Account using the Service Principal credentials supplied via
    # the ARM_* environment variables (ARM_CLIENT_ID, ARM_CLIENT_SECRET,
    # ARM_TENANT_ID, ARM_SUBSCRIPTION_ID). The backend obtains a storage
    # access key at init time and uses it for blob I/O.
    #
    # Setting this to `true` would instead use the SP's Azure AD identity
    # directly against the Storage Account's data plane; that requires the
    # SP to have `Storage Blob Data Contributor` (or equivalent) on the
    # account. We stay on `false` here so a fresh SP without data-plane
    # RBAC can still bootstrap the backend on first run.
    use_azuread_auth = false
  }
}
