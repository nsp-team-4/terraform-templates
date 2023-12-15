# Network security group
resource "azurerm_network_security_group" "this" {
  location            = azurerm_resource_group.this.location
  name                = local.network_security_group_name
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
  network_security_group_name = local.network_security_group_name
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
