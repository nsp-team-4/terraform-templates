# Event Hub Namespace
resource "azurerm_eventhub_namespace" "this" {
  name                = local.eventhub_namespace_name
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
  name                = "ais-events-endpoint-${var.env_name}"
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
