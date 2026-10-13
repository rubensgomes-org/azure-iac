# modules/app-gateway/main.tf
# -----------------------------------------------------------------------------
# Publishes one Container App to the internet through an Application Gateway
# v2 in front of the internal Container App Environment (module 11):
#
#   client --HTTP:80--> pip-<workload>agw-<env> / agw-<workload>-<env>
#          --HTTPS:443, Host=<app fqdn>--> CAE static IP --> Container App
#
# Design decisions (fixed here, not variables):
#
# * **Standard_v2, autoscale 0-2.** No WAF. The fixed hourly charge applies
#   while the gateway exists; capacity units scale with load.
#
# * **HTTP-only listener.** HTTPS needs a custom domain and a certificate.
#
# * **HTTPS backend with the app FQDN as host name.** The environment routes
#   by Host header and redirects HTTP to HTTPS. Its certificate is issued by
#   a well-known CA for `*.<cae_default_domain>`, so no trusted root
#   certificate is configured.
#
# * **NSG rules owned here**, not by module 02, so destroying the gateway
#   also closes the public port. GatewayManager 65200-65535 is required by
#   Azure before a v2 gateway can be created on a subnet with an NSG.
#
# This project's source code and documentation were generated with the
# assistance of Artificial Intelligence (AI). For more information, please
# refer to the `AI_DISCLAIMER.md` document located in the project's root
# directory.
# -----------------------------------------------------------------------------

locals {
  name = "agw-${var.workload}-${var.env}"
  nsg  = provider::azurerm::parse_resource_id(var.nsg_id)

  min_capacity = 0
  max_capacity = 2

  frontend_port    = 80
  backend_port     = 443
  request_timeout  = 300 # seconds; agent prompts make several LLM calls.
  probe_interval   = 30
  probe_timeout    = 10
  probe_unhealthy  = 3
  ssl_policy_name  = "AppGwSslPolicy20220101"
  gateway_mgr_port = "65200-65535"

  # Child block names, referenced across blocks.
  gateway_ip_config  = "gateway-ip"
  frontend_ip_config = "frontend-public"
  frontend_port_name = "port-http"
  backend_pool       = "pool-cae"
  backend_settings   = "settings-cae-https"
  probe              = "probe-health"
  listener           = "listener-http"
  routing_rule       = "rule-http"
}

# -----------------------------------------------------------------------------
# NSG rules on the gateway subnet
# -----------------------------------------------------------------------------
resource "azurerm_network_security_rule" "gateway_manager" {
  name                        = "AllowGatewayManagerInbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = local.gateway_mgr_port
  source_address_prefix       = "GatewayManager"
  destination_address_prefix  = "*"
  resource_group_name         = local.nsg.resource_group_name
  network_security_group_name = local.nsg.resource_name
}

resource "azurerm_network_security_rule" "http" {
  name                        = "AllowHttpInbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(local.frontend_port)
  source_address_prefixes     = var.public_source_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = local.nsg.resource_group_name
  network_security_group_name = local.nsg.resource_name
}

# -----------------------------------------------------------------------------
# Public IP
# -----------------------------------------------------------------------------
resource "azurerm_public_ip" "this" {
  name                = "pip-${var.workload}agw-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.dns_label

  tags = merge(var.tags, { component = "app-gateway" })
}

# -----------------------------------------------------------------------------
# Application Gateway
# -----------------------------------------------------------------------------
resource "azurerm_application_gateway" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = local.min_capacity
    max_capacity = local.max_capacity
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = local.ssl_policy_name
  }

  gateway_ip_configuration {
    name      = local.gateway_ip_config
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_config
    public_ip_address_id = azurerm_public_ip.this.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = local.frontend_port
  }

  backend_address_pool {
    name         = local.backend_pool
    ip_addresses = [var.backend_ip_address]
  }

  backend_http_settings {
    name                  = local.backend_settings
    cookie_based_affinity = "Disabled"
    port                  = local.backend_port
    protocol              = "Https"
    host_name             = var.backend_host_name
    request_timeout       = local.request_timeout
    probe_name            = local.probe
  }

  probe {
    name                = local.probe
    protocol            = "Https"
    host                = var.backend_host_name
    path                = var.health_probe_path
    interval            = local.probe_interval
    timeout             = local.probe_timeout
    unhealthy_threshold = local.probe_unhealthy

    match {
      status_code = ["200-399"]
    }
  }

  http_listener {
    name                           = local.listener
    frontend_ip_configuration_name = local.frontend_ip_config
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.routing_rule
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = local.listener
    backend_address_pool_name  = local.backend_pool
    backend_http_settings_name = local.backend_settings
  }

  tags = merge(var.tags, { component = "app-gateway" })

  depends_on = [azurerm_network_security_rule.gateway_manager]
}
