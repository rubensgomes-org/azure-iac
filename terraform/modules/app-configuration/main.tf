# modules/app-configuration/main.tf
# -----------------------------------------------------------------------------
# Provisions one App Configuration store per env plus the RBAC grant that lets
# the shared UAMI read key-values. Consumers:
#   - Key Vault (module 06) — grants this store's system-assigned identity
#     `Key Vault Secrets User`.
#   - Container Apps (module 12) — read settings via DefaultAzureCredential,
#     using the endpoint injected as APP_CONFIG_ENDPOINT.
#
# Individual key-values are NOT managed here; writing them would need a
# data-plane role for the Terraform SP.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Dev-friendly settings (locals)
# -----------------------------------------------------------------------------
#   - `free` SKU: no cost, but one free store per subscription and no soft
#     delete, so a destroy frees the name immediately.
#   - `local_auth_enabled = false`: access keys off; Entra ID RBAC only.
#   - Public network access: RBAC is the auth gate, as for Key Vault.
locals {
  name                  = "appcs-${var.workload}-${var.env}"
  sku                   = "free"
  local_auth_enabled    = false
  public_network_access = "Enabled"
  max_name_length       = 50
}

# -----------------------------------------------------------------------------
# App Configuration store
# -----------------------------------------------------------------------------
# Name pattern: CAF `appcs-<workload>-<env>` (e.g. "appcs-rgomes-lab"). Names
# are globally unique (`<name>.azconfig.io`); there is no random suffix.
resource "azurerm_app_configuration" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  sku                   = local.sku
  local_auth_enabled    = local.local_auth_enabled
  public_network_access = local.public_network_access

  # Principal that module 06 grants Key Vault access to.
  identity {
    type = "SystemAssigned"
  }

  tags = merge(
    var.tags,
    { component = "app-configuration" },
  )

  lifecycle {
    precondition {
      condition     = length(local.name) <= local.max_name_length
      error_message = "App Configuration name ${local.name} exceeds ${local.max_name_length} chars. Shorten workload or env."
    }
  }
}

# -----------------------------------------------------------------------------
# RBAC — App Configuration Data Reader for the shared UAMI
# -----------------------------------------------------------------------------
# Read-only by design: writes go through Terraform or an operator.
resource "azurerm_role_assignment" "uami_data_reader" {
  scope                = azurerm_app_configuration.this.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = var.uami_principal_id

  # Skips the Entra lookup that can fail on a just-created identity.
  principal_type = "ServicePrincipal"
}
