# Resource group
resource "azurerm_resource_group" "this" {
  name     = "north-sea-port-hz"
  location = "westeurope"
}
