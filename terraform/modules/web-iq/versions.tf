# modules/web-iq/versions.tf
# -----------------------------------------------------------------------------
# Terraform CLI and provider constraints. Child modules declare providers but
# do not configure them; the calling root does.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}
