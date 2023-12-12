terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.84.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.10.0"
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
  name     = "north-sea-port-hz"
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
}

# Backend pool
resource "azurerm_lb_backend_address_pool" "this" {
  loadbalancer_id = azurerm_lb.this.id
  name            = "ais-backend-pool"
}

# Backend pool address
resource "azurerm_lb_backend_address_pool_address" "this" {
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id
  name                    = "container-group-address"
  virtual_network_id      = azurerm_virtual_network.this.id
  ip_address              = azurerm_container_group.this.ip_address
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

  depends_on = [
    azurerm_network_security_group.this,
  ]
}

# Network security group association for the default subnet
resource "azurerm_subnet_network_security_group_association" "this" {
  network_security_group_id = azurerm_network_security_group.this.id
  subnet_id                 = azurerm_subnet.default.id
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
    "10.1.0.0/16", # TODO: Is this necessary? (Stream Analytics)
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

    virtual_network_rule {
      subnet_id = azurerm_subnet.stream.id
    }
  }
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
    "Microsoft.Storage",
  ]
}

# Private DNS Zone for the Event Hub Namespace
resource "azurerm_private_dns_zone" "events" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

# Private DNS Zone Group for the Event Hub Namespace
resource "azurerm_private_dns_zone_virtual_network_link" "events" {
  name                  = "ais-events-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.events.name
  resource_group_name   = azurerm_resource_group.this.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

# Private endpoint for the Event Hub Namespace
resource "azurerm_private_endpoint" "events" {
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

  private_dns_zone_group {
    name = "ais-events-dns-zone-group"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.events.id,
    ]
  }
}

# Storage account for the Event Hub Namespace
resource "azurerm_storage_account" "events" {
  name                      = var.storage_account_name
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  access_tier               = "Cool"
  queue_encryption_key_type = "Account"
  table_encryption_key_type = "Account"

  blob_properties {
    delete_retention_policy {
      days = 1
    }
  }

  network_rules {
    default_action = "Deny"
    ip_rules       = var.allowed_ips # TODO: Check if there is another way to do this, because this is not the most secure way to give NSP access to the data (e.g. Event Hub).
    virtual_network_subnet_ids = [
      azurerm_subnet.events.id,
    ]
  }
}

# Private DNS Zone for the Storage Account
resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
}

# Private DNS Zone Group for the Storage Account
resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  name                  = "ais-storage-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  resource_group_name   = azurerm_resource_group.this.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

# Private endpoint for the Storage Account
resource "azurerm_private_endpoint" "storage" {
  name                = "ais-storage-endpoint"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.events.id

  private_service_connection {
    name                           = "ais-storage-connection"
    private_connection_resource_id = azurerm_storage_account.events.id
    is_manual_connection           = false
    subresource_names = [
      "blob",
    ]
  }

  private_dns_zone_group {
    name = "ais-storage-dns-zone-group"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.storage.id,
    ]
  }
}

# Stream Analytics subnet
resource "azurerm_subnet" "stream" {
  name = "stream"
  address_prefixes = [
    "10.1.0.0/24",
  ]
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  service_endpoints = [
    "Microsoft.EventHub",
  ]

  delegation {
    name = "Microsoft.StreamAnalytics/streamingJobs"

    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
      name = "Microsoft.StreamAnalytics/streamingJobs"
    }
  }
}

# Stream Analytics Job
resource "azapi_resource" "this" {
  # The latest API provider is the 2021-10-01-preview, while the Virtual Network has been released in June of 2023.
  # This is why it's not possible to enable the Virtual Network for the Stream Analytics Job from Terraform.
  type      = "Microsoft.StreamAnalytics/streamingJobs@2021-10-01-preview"
  name      = "stream-ais-job"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    properties = {
      compatibilityLevel   = "1.2"
      contentStoragePolicy = "JobStorageAccount"
      externals = {
        container = var.stream_analytics_job_output_name
        path      = "year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}"
        storageAccount = {
          accountKey         = azurerm_storage_account.events.primary_access_key
          accountName        = azurerm_storage_account.events.name
          authenticationMode = "Msi"
        }
      }
      jobStorageAccount = {
        accountName        = azurerm_storage_account.events.name
        authenticationMode = "Msi"
      }
      sku = {
        capacity = var.stream_analytics_job_capacity
        name     = "StandardV2"
      }
      transformation = null
    }
    sku = {
      capacity = var.stream_analytics_job_capacity
      name     = "StandardV2"
    }
  })
  
  response_export_values = [
    "id",
    "name",
  ]
}

# Add Azure Event Hubs Data Receiver role assignment to the Managed Identity of the Stream Analytics Job.
resource "azurerm_role_assignment" "stream_event_hub_role" {
  scope                = azurerm_eventhub_namespace.this.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azapi_resource.this.identity[0].principal_id
}

# Add the Storage Blob Data Contributor role assignment to the Managed Identity of the Stream Analytics Job.
resource "azurerm_role_assignment" "stream_blob_role" {
  scope                = azurerm_storage_account.events.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.this.identity[0].principal_id
}

# Add the Storage Queue Data Contributor role assignment to the Managed Identity of the Stream Analytics Job.
resource "azurerm_role_assignment" "stream_table_role" {
  scope                = azurerm_storage_account.events.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azapi_resource.this.identity[0].principal_id
}

# Now update the Stream Analytics Job with the correct transformation.
resource "azapi_update_resource" "this" {
  type      = "Microsoft.StreamAnalytics/streamingJobs@2021-10-01-preview"
  resource_id = replace(jsondecode(azapi_resource.this.output).id, "streamingjobs", "streamingJobs")
  body = jsonencode({
    properties = {
      externals = {
        container = var.stream_analytics_job_output_name
        path      = "year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}"
        storageAccount = {
          accountKey         = azurerm_storage_account.events.primary_access_key
          accountName        = azurerm_storage_account.events.name
          authenticationMode = "Msi"
        }
      }
      transformation = {
        name = "main",
        properties = {
          query = templatefile("./sql/stream-analytics-job.sql", {
            input_name  = var.stream_analytics_job_input_name,
            output_name = var.stream_analytics_job_output_name,
          }),
          streamingUnits = var.stream_analytics_job_capacity,
        }
      }
    }
  })
  
  response_export_values = [
    "id",
    "name",
  ]
  
  depends_on = [
    azapi_resource.this,
    azurerm_role_assignment.stream_event_hub_role,
    azurerm_role_assignment.stream_blob_role,
    azurerm_role_assignment.stream_table_role,
  ]
}

# Stream Analytics Job Input
resource "azurerm_stream_analytics_stream_input_eventhub_v2" "this" {
  name                      = var.stream_analytics_job_input_name
  stream_analytics_job_id   = replace(jsondecode(azapi_update_resource.this.output).id, "streamingjobs", "streamingJobs")
  eventhub_name             = azurerm_eventhub.this.name
  servicebus_namespace      = azurerm_eventhub_namespace.this.name
  authentication_mode       = "Msi"
  shared_access_policy_key  = azurerm_eventhub_namespace.this.default_primary_key
  shared_access_policy_name = "RootManageSharedAccessKey"

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Output Blob for the Stream Analytics Job
resource "azurerm_stream_analytics_output_blob" "this" {
  name                      = var.stream_analytics_job_output_name
  resource_group_name       = azurerm_resource_group.this.name
  stream_analytics_job_name = jsondecode(azapi_update_resource.this.output).name
  date_format               = "yyyy-MM-dd"
  path_pattern              = "{datetime:yyyy}/{datetime:MM}/{datetime:dd}/{datetime:HH}"
  time_format               = "HH"
  storage_account_name      = azurerm_storage_account.events.name
  authentication_mode       = "Msi"
  storage_account_key       = azurerm_storage_account.events.primary_access_key
  storage_container_name    = var.stream_analytics_job_output_name

  serialization {
    type     = "Json"
    encoding = "UTF8"
    format   = "LineSeparated"
  }
}
