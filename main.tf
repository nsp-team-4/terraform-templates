terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80.0"
    }
  }

  required_version = ">= 1.6.3"
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

# Resource group
resource "azurerm_resource_group" "this" {
  name     = "north-sea-port"
  location = "westeurope"
}

# Container Instance
resource "azurerm_container_group" "this" {
  ip_address_type     = "Private"
  location            = azurerm_resource_group.this.location
  name                = "ais-receiver"
  os_type             = "Linux"
  resource_group_name = azurerm_resource_group.this.name
  restart_policy      = "OnFailure"
  subnet_ids = [
    azurerm_subnet.default.id,
  ]

  container {
    cpu    = 1
    image  = "auxority/ais-receiver"
    memory = 1.5
    name   = "ais-receiver"
    environment_variables = {
      EVENT_HUB_NAME = azurerm_eventhub.this.name
    }
    secure_environment_variables = {
      ENDPOINT_CONNECTION_STRING = azurerm_eventhub_namespace.this.default_primary_connection_string
    }

    ports {
      port = 2001
    }
  }

  depends_on = [
    azurerm_subnet.default,
    azurerm_eventhub_namespace.this,
  ]
}

# Load balancer
resource "azurerm_lb" "this" {
  name                = "ais-load-balancer"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "ais-frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.this.id
  }

  depends_on = [
    azurerm_resource_group.this,
  ]
}

# Backend pool
resource "azurerm_lb_backend_address_pool" "this" {
  loadbalancer_id = azurerm_lb.this.id
  name            = "ais-backend-pool"

  depends_on = [
    azurerm_lb.this,
  ]
}

# Backend pool address
resource "azurerm_lb_backend_address_pool_address" "this" {
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id
  name                    = "container-group-address"
  virtual_network_id      = azurerm_virtual_network.this.id
  ip_address              = azurerm_container_group.this.ip_address

  depends_on = [
    azurerm_lb_backend_address_pool.this,
    azurerm_virtual_network.this,
  ]
}

# Inbound NAT rule
resource "azurerm_lb_nat_rule" "this" {
  resource_group_name            = azurerm_resource_group.this.name
  backend_address_pool_id        = azurerm_lb_backend_address_pool.this.id
  backend_port                   = 2001
  frontend_ip_configuration_name = "ais-frontend-ip-config"
  frontend_port_start            = 2001
  frontend_port_end              = 2001
  loadbalancer_id                = azurerm_lb.this.id
  name                           = "allow-port-2001-rule"
  protocol                       = "Tcp"
  depends_on = [
    azurerm_lb_backend_address_pool.this,
  ]
}

# Network security group
resource "azurerm_network_security_group" "this" {
  location            = azurerm_resource_group.this.location
  name                = "network-security-group"
  resource_group_name = azurerm_resource_group.this.name
}

# Network security rule
resource "azurerm_network_security_rule" "this" {
  resource_group_name         = azurerm_resource_group.this.name
  access                      = "Allow"
  destination_address_prefix  = "10.0.0.0/24"
  destination_port_range      = "2001"
  direction                   = "Inbound"
  name                        = "AllowAnyCustom2001Inbound"
  network_security_group_name = "network-security-group"
  priority                    = 100
  protocol                    = "Tcp"
  source_address_prefixes     = var.allowed_ips
  source_port_range           = "*"
}

# Network security group association for the default subnet
resource "azurerm_subnet_network_security_group_association" "this" {
  network_security_group_id = azurerm_network_security_group.this.id
  subnet_id                 = azurerm_subnet.default.id

  depends_on = [
    azurerm_network_security_group.this,
    azurerm_subnet.default,
  ]
}

# Public IP
resource "azurerm_public_ip" "this" {
  allocation_method   = "Static"
  domain_name_label   = var.domain_name_label
  location            = azurerm_resource_group.this.location
  name                = "ais-public-ip"
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
}

# Virtual network
resource "azurerm_virtual_network" "this" {
  address_space = [
    "10.0.0.0/16",
  ]
  location            = azurerm_resource_group.this.location
  name                = "north-sea-port-vnet"
  resource_group_name = azurerm_resource_group.this.name
}

# Default subnet
resource "azurerm_subnet" "default" {
  name = "default"
  address_prefixes = [
    "10.0.0.0/24",
  ]
  resource_group_name = azurerm_resource_group.this.name
  service_endpoints = [
    "Microsoft.KeyVault",
    "Microsoft.Storage",
  ]
  virtual_network_name = azurerm_virtual_network.this.name

  delegation {
    name = "Microsoft.ContainerInstance.containerGroups"

    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
      name = "Microsoft.ContainerInstance/containerGroups"
    }
  }
}

# Event Hub Namespace
resource "azurerm_eventhub_namespace" "this" {
  name                = var.eventhub_namespace_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard"

  network_rulesets {
    default_action = "Deny"

    virtual_network_rule {
      subnet_id = azurerm_subnet.events.id
    }
  }

  depends_on = [
    azurerm_subnet.events,
  ]
}

# Event Hub
resource "azurerm_eventhub" "this" {
  name                = "ais-events"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = azurerm_resource_group.this.name
  partition_count     = 1
  message_retention   = 1
}

# Events subnet
resource "azurerm_subnet" "events" {
  name = "events"
  address_prefixes = [
    "10.0.1.0/24",
  ]
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  service_endpoints = [
    "Microsoft.EventHub",
  ]
}

# Microsoft.Network/privateEndpoints/privateDnsZoneGroups
# Microsoft.Network/privateEndpoints
# Microsoft.Network/privateDnsZones/virtualNetworkLinks
# Microsoft.EventHub/namespaces/privateEndpointConnections

# Private DNS Zone
resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

# Private DNS Zone Group
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "ais-events-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  resource_group_name   = azurerm_resource_group.this.name
  virtual_network_id    = azurerm_virtual_network.this.id

  depends_on = [
    azurerm_virtual_network.this,
  ]
}

# Private endpoint
resource "azurerm_private_endpoint" "this" {
  name                = "ais-events-endpoint"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.events.id

  private_service_connection {
    name                           = "ais-events-connection"
    private_connection_resource_id = azurerm_eventhub_namespace.this.id
    is_manual_connection           = false
    subresource_names = [
      "namespace",
    ]
  }

  depends_on = [
    azurerm_eventhub_namespace.this,
    azurerm_subnet.events,
  ]
}
