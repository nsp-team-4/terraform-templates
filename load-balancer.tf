# Load balancer
resource "azurerm_lb" "this" {
  name                = "ais-load-balancer-${var.env_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = var.frontend_ip_name
    public_ip_address_id = azurerm_public_ip.this.id
  }
}

# Public IP
resource "azurerm_public_ip" "this" {
  allocation_method   = "Static"
  domain_name_label   = local.domain_name_label
  location            = azurerm_resource_group.this.location
  name                = "ais-public-ip-${var.env_name}"
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
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
  frontend_ip_configuration_name = var.frontend_ip_name
  frontend_port_start            = 2001
  frontend_port_end              = 2001
  loadbalancer_id                = azurerm_lb.this.id
  name                           = "allow-port-2001-rule"
  protocol                       = "Tcp"
}
