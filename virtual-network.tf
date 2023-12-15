# Virtual network
resource "azurerm_virtual_network" "this" {
  address_space = [
    "10.0.0.0/16",
    "10.1.0.0/16",
  ]
  location            = azurerm_resource_group.this.location
  name                = "north-sea-port-vnet-${var.env_name}"
  resource_group_name = azurerm_resource_group.this.name
}

# Container Group subnet
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

# Event Hub namespace subnet
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