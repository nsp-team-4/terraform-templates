
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
    ip_rules       = var.allowed_ips
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
