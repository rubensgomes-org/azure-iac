# envs/dev/09-postgresql/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI + provider version constraints for the postgresql root config.
# Kept consistent with the rest of the estate.
#
# This root calls `../../../modules/postgresql/` (azurerm + random + null)
# and adds `http` (fetching the runner's public IP for the firewall rule).
# It reads state from `01-resource-groups` and `04-managed-identities`.
#
# `azuread` is intentionally NOT declared. Earlier iterations looked up the
# Entra admin group's display name via `data.azuread_group`, but that call
# requires `Directory.Read.All` / `Group.Read.All` on the Terraform SP — a
# playground SP typically lacks both, and granting them needs tenant admin
# consent. The group name is now passed explicitly via
# `var.pg_entra_admin_group_name` from env.tfvars.
# -----------------------------------------------------------------------------

terraform {
  required_version = "~> 1.15"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
  }
}
