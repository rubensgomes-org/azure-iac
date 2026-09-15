# bootstrap-backend/versions.tf
# -----------------------------------------------------------------------------
# Purpose
# -----------------------------------------------------------------------------
# Declares the Terraform CLI version and the provider source + version
# constraints required by the "bootstrap-backend" module.
#
# This module bootstraps the remote state backend (Resource Group, Storage
# Account, blob container, RBAC assignment, and optional RG lock) that every
# other module in this repository uses to store its state. Because it is the
# foundation of the state layer, the tooling versions used to apply it must be
# reproducible across engineer workstations and CI runners.
#
# -----------------------------------------------------------------------------
# How Terraform resolves versions
# -----------------------------------------------------------------------------
#   1. `required_version` gates the Terraform CLI itself. `terraform init` and
#      subsequent commands refuse to run when the local CLI does not satisfy
#      this constraint.
#   2. `required_providers` names each provider, its canonical source address
#      in the Terraform Registry, and an acceptable version range.
#   3. On `terraform init`, Terraform selects the newest provider version that
#      satisfies the constraint AND is compatible with the checksums recorded
#      in `.terraform.lock.hcl` (the dependency lock file). The lock file is
#      committed to source control so every user/CI run installs the exact
#      same provider build.
#   4. To upgrade the provider within the allowed range, run
#      `terraform init -upgrade`; this refreshes the lock file.
#
# -----------------------------------------------------------------------------
# The pessimistic constraint operator "~>"
# -----------------------------------------------------------------------------
# `~> X.Y`   allows any version >= X.Y and < (X+1).0   (locks the major)
# `~> X.Y.Z` allows any version >= X.Y.Z and < X.(Y+1) (locks the minor)
#
# We use the two-segment form for PROVIDERS ("~> 5.4") so patch AND minor
# updates flow in automatically, while a breaking major bump requires a
# deliberate edit to this file.
#
# The Terraform CLI constraint is a two-clause RANGE rather than a "~>" form,
# because no "~>" expression says what is meant here. The floor has to be an
# exact patch release (1.16.0), and `~> 1.16.0` would pin the minor as well,
# shutting out 1.17. `>= 1.16.0, < 2.0` keeps the same effect the two-segment
# form had -- minor and patch flow in, 2.x needs a deliberate edit -- while
# putting the floor where it belongs.
# -----------------------------------------------------------------------------

terraform {
  # ---------------------------------------------------------------------------
  # Terraform CLI constraint
  # ---------------------------------------------------------------------------
  # Accepts Terraform >= 1.16.0 and < 2.0.0. The 1.x line preserves the HCL
  # dialect and state file format used throughout this repo. A future 2.x
  # release would likely require migration work, so it is intentionally
  # excluded here.
  #
  # The floor is a FLOOR, not a pin: `terraform init` refuses to run on an
  # older CLI, so raising it obsoletes every workstation still on 1.15.x.
  # Every workflow in .github/workflows/ pins a build that satisfies it; the
  # two move together or CI stops matching local runs.
  required_version = ">= 1.16.0, < 2.0"

  # ---------------------------------------------------------------------------
  # Provider constraints
  # ---------------------------------------------------------------------------
  required_providers {
    # -------------------------------------------------------------------------
    # hashicorp/azurerm
    # -------------------------------------------------------------------------
    # The official HashiCorp provider for Azure Resource Manager. Used in
    # main.tf to create:
    #   - azurerm_resource_group.tfstate
    #   - azurerm_storage_account.tfstate (with versioning + soft delete)
    #   - azurerm_storage_container.tfstate
    #   - azurerm_role_assignment.state_blob_contributor
    #   - azurerm_management_lock.tfstate_rg_lock (optional)
    #
    # `source` must be the fully-qualified registry address; without it,
    # Terraform 0.13+ cannot locate the provider.
    #
    # Version "~> 5.4" accepts >= 5.4.0 and < 6.0.0. The 5.x line matches the
    # AzureRM v5 schema our resource definitions are written against. Major
    # version bumps rename attributes and require code changes, so they are
    # held back until a coordinated upgrade -- the move off 4.x, for one,
    # rewrote the private DNS zone virtual network link in modules/networking.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }

    # -------------------------------------------------------------------------
    # aztfmod/azurecaf
    # -------------------------------------------------------------------------
    # Community provider (maintained by the Azure Terraform Modules org) that
    # generates resource names conforming to the Microsoft Cloud Adoption
    # Framework (CAF) naming convention. It exposes:
    #   - `azurecaf_name` resource / data source: builds deterministic names
    #     from a resource type, prefixes, suffixes, and an optional random
    #     component, while enforcing Azure's per-resource length and
    #     character-set rules (e.g. storage accounts: 3-24 lowercase alnum).
    #
    # Using this provider centralises naming policy so the bootstrap-backend
    # storage account, resource group, and any downstream resources stay
    # consistent with the rest of the estate and pass CAF compliance checks.
    #
    # Version "~> 1.2" accepts >= 1.2.0 and < 2.0.0. The 1.x line has a
    # stable resource schema and is still the newest STABLE line: 2.0.0 exists
    # only as a preview, which Terraform will not select on its own anyway.
    azurecaf = {
      source  = "aztfmod/azurecaf"
      version = "~> 1.2"
    }

    # -------------------------------------------------------------------------
    # azure/azapi
    # -------------------------------------------------------------------------
    # Microsoft's official "escape hatch" provider that speaks directly to
    # the Azure Resource Manager REST API. It is used to configure resources
    # or properties that the `azurerm` provider has not yet exposed (new
    # preview features, brand-new resource types, or fine-grained sub-
    # properties).
    #
    # Typical resources:
    #   - `azapi_resource`        - create/update any ARM resource by type
    #                               and API version.
    #   - `azapi_update_resource` - patch a subset of properties on a
    #                               resource managed elsewhere.
    #   - `azapi_resource_action` - invoke ARM POST actions (e.g. listKeys).
    #
    # In this module it is available as a forward-compatibility hedge: if a
    # storage-account hardening setting lands in Azure before `azurerm`
    # supports it, we can apply it via `azapi` without waiting for a
    # provider release.
    #
    # Version "~> 2.12" accepts >= 2.12.0 and < 3.0.0. The 2.x line ships
    # the current typed-schema experience; 1.x used a JSON `body` string
    # and is not backwards compatible.
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.12"
    }
  }
}
