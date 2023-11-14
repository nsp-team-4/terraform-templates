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

# Allowed IP prefixes (CIDR notation)
variable "allowed_ip_prefixes" {
  description = "The IP prefixes that are allowed to connect to the AIS receiver container."
  type        = list(string)
  default = [
    "86.92.2.242",
    "212.115.197.130",
  ]
}

# Domain name label for the public IP
variable "domain_name_label" {
  description = "The domain name label for the public IP."
  type        = string
  default     = "ais-receiver"
}

# Storage account name for events
variable "storage_account_name" {
  description = "The name of the storage account for events."
  type        = string
  default     = "nspaisstorageaccount"
}

# Event hub namespace name
variable "eventhub_namespace_name" {
  description = "The name of the event hub namespace."
  type        = string
  default     = "nspaisevents"
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
  container {
    cpu    = 1
    image  = "auxority/ais-receiver"
    memory = 1
    name   = "ais-receiver"
    secure_environment_variables = {
      ENDPOINT_CONNECTION_STRING = azurerm_eventhub_namespace.this.default_primary_connection_string
    }
    ports {
      port = 2001
    }
  }
  subnet_ids = [
    azurerm_subnet.default.id,
  ]
  depends_on = [
    azurerm_resource_group.this,
    azurerm_virtual_network.this,
    azurerm_subnet.default,
  ]
}

# Event Hub Namespace
resource "azurerm_eventhub_namespace" "this" {
  auto_inflate_enabled          = true
  maximum_throughput_units      = 2
  location                      = azurerm_resource_group.this.location
  name                          = var.eventhub_namespace_name
  resource_group_name           = azurerm_resource_group.this.name
  sku                           = "Standard"
  public_network_access_enabled = false
  zone_redundant                = false
  depends_on = [
    azurerm_resource_group.this,
  ]
}

# Event Hub
resource "azurerm_eventhub" "this" {
  message_retention   = 1
  name                = "ais-event-hub"
  namespace_name      = azurerm_eventhub_namespace.this.name
  partition_count     = 1
  resource_group_name = azurerm_resource_group.this.name
  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = 60
    size_limit_in_bytes = 62914560
    destination {
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = "decoded-messages"
      name                = "EventHubArchive.AzureBlockBlob"
      storage_account_id  = azurerm_storage_account.events.id
    }
  }
  depends_on = [
    azurerm_eventhub_namespace.this,
  ]
}

# Authorization rule for the event hub
resource "azurerm_eventhub_authorization_rule" "this" {
  eventhub_name       = azurerm_eventhub.this.name
  listen              = true
  name                = "stream_ais-event-hub-policy"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = azurerm_resource_group.this.name
  depends_on = [
    azurerm_eventhub.this,
  ]
}

# The default consumer group
resource "azurerm_eventhub_consumer_group" "default" {
  eventhub_name       = azurerm_eventhub.this.name
  name                = "default"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = azurerm_resource_group.this.name
  depends_on = [
    azurerm_eventhub.this,
  ]
}

# Consumer group for events
resource "azurerm_eventhub_consumer_group" "events" {
  eventhub_name       = azurerm_eventhub.this.name
  name                = "stream_ais-event-hub-consumer-group"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = azurerm_resource_group.this.name
  depends_on = [
    azurerm_eventhub.this,
  ]
}

# Load balancer
resource "azurerm_lb" "this" {
  location            = azurerm_resource_group.this.location
  name                = "ais-load-balancer"
  resource_group_name = azurerm_resource_group.this.name
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
  ip_address              = "10.0.0.4"
  depends_on = [
    azurerm_virtual_network.this,
  ]
}

# Inbound NAT rule
resource "azurerm_lb_nat_rule" "this" {
  backend_address_pool_id        = azurerm_lb_backend_address_pool.this.id
  backend_port                   = 2001
  frontend_ip_configuration_name = "ais-frontend-ip-config"
  frontend_port_end              = 2001
  frontend_port_start            = 2001
  loadbalancer_id                = azurerm_lb.this.id
  name                           = "allow-port-2001-rule"
  protocol                       = "Tcp"
  resource_group_name            = azurerm_resource_group.this.name
  depends_on = [
    azurerm_lb_backend_address_pool.this,
  ]
}

# Network security group
resource "azurerm_network_security_group" "this" {
  location            = azurerm_resource_group.this.location
  name                = "network-security-group"
  resource_group_name = azurerm_resource_group.this.name
  depends_on = [
    azurerm_resource_group.this,
  ]
}

# Network security rule
resource "azurerm_network_security_rule" "this" {
  access                      = "Allow"
  destination_address_prefix  = "10.0.0.0/24"
  destination_port_range      = "2001"
  direction                   = "Inbound"
  name                        = "AllowAnyCustom2001Inbound"
  network_security_group_name = "network-security-group"
  priority                    = 100
  protocol                    = "Tcp"
  resource_group_name         = azurerm_resource_group.this.name
  source_address_prefixes     = var.allowed_ip_prefixes
  source_port_range           = "*"
  depends_on = [
    azurerm_network_security_group.this,
  ]
}

# Private DNS zone for the storage account
resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  depends_on = [
    azurerm_resource_group.this,
  ]
}

# DNS record for the storage account
resource "azurerm_private_dns_a_record" "storage" {
  name                = "nspstoragednsrecord"
  records             = ["10.0.1.5"]
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 3600
  zone_name           = "privatelink.blob.core.windows.net"
  depends_on = [
    azurerm_private_dns_zone.storage,
  ]
}

# Virtual network link for the storage account
resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  name                  = "storage-virtual-network-link"
  private_dns_zone_name = "privatelink.blob.core.windows.net"
  resource_group_name   = azurerm_resource_group.this.name
  virtual_network_id    = azurerm_virtual_network.this.id
  depends_on = [
    azurerm_private_dns_zone.storage,
    azurerm_virtual_network.this,
  ]
}

# Private DNS zone for the event hub
resource "azurerm_private_dns_zone" "events" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  depends_on = [
    azurerm_resource_group.this,
  ]
}

# DNS record for the event hub
resource "azurerm_private_dns_a_record" "events" {
  name                = azurerm_eventhub_namespace.this.name
  records             = ["10.0.1.4"]
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 3600
  zone_name           = "privatelink.servicebus.windows.net"
  depends_on = [
    azurerm_private_dns_zone.events,
  ]
}

# Virtual network link for the event hub
resource "azurerm_private_dns_zone_virtual_network_link" "events" {
  name                  = "events-virtual-network-link"
  private_dns_zone_name = "privatelink.servicebus.windows.net"
  resource_group_name   = azurerm_resource_group.this.name
  virtual_network_id    = azurerm_virtual_network.this.id
  depends_on = [
    azurerm_private_dns_zone.events,
    azurerm_virtual_network.this,
  ]
}

# Private endpoint for the event hub
resource "azurerm_private_endpoint" "events" {
  location            = azurerm_container_group.this.location
  name                = "eventhubs-endpoint"
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.events.id
  private_service_connection {
    is_manual_connection           = false
    name                           = "eventhubs-private-endpoint"
    private_connection_resource_id = azurerm_eventhub_namespace.this.id
    subresource_names              = ["namespace"]
  }
  depends_on = [
    azurerm_eventhub_namespace.this,
    azurerm_subnet.events,
  ]
}

# Private endpoint for the storage account
resource "azurerm_private_endpoint" "storage" {
  location            = azurerm_resource_group.this.location
  name                = "storage-endpoint"
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.events.id
  private_service_connection {
    is_manual_connection           = false
    name                           = "storage-private-endpoint"
    private_connection_resource_id = azurerm_storage_account.events.id
    subresource_names              = ["blob"]
  }
  depends_on = [
    azurerm_subnet.events,
    azurerm_storage_account.events,
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
  depends_on = [
    azurerm_resource_group.this,
  ]
}

# Virtual network
resource "azurerm_virtual_network" "this" {
  address_space       = ["10.0.0.0/24", "10.0.1.0/24"]
  location            = azurerm_resource_group.this.location
  name                = "north-sea-port-vnet"
  resource_group_name = azurerm_resource_group.this.name
  depends_on = [
    azurerm_resource_group.this,
  ]
}

# Default subnet
resource "azurerm_subnet" "default" {
  address_prefixes     = ["10.0.0.0/24"]
  name                 = "default"
  resource_group_name  = azurerm_resource_group.this.name
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.Storage"]
  virtual_network_name = "north-sea-port-vnet"
  delegation {
    name = "Microsoft.ContainerInstance.containerGroups"
    service_delegation {
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      name    = "Microsoft.ContainerInstance/containerGroups"
    }
  }
  depends_on = [
    azurerm_virtual_network.this,
  ]
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

# Events subnet
resource "azurerm_subnet" "events" {
  address_prefixes     = ["10.0.1.0/24"]
  name                 = "eventhubs-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  service_endpoints    = ["Microsoft.EventHub", "Microsoft.Storage"]
  virtual_network_name = "north-sea-port-vnet"
  depends_on = [
    azurerm_virtual_network.this,
  ]
}

# Storage account for the events
resource "azurerm_storage_account" "events" {
  account_replication_type         = "LRS"
  account_tier                     = "Standard"
  cross_tenant_replication_enabled = false
  default_to_oauth_authentication  = true
  location                         = azurerm_resource_group.this.location
  name                             = var.storage_account_name
  queue_encryption_key_type        = "Account"
  resource_group_name              = azurerm_resource_group.this.name
  table_encryption_key_type        = "Account"
  depends_on = [
    azurerm_resource_group.this,
  ]
}
