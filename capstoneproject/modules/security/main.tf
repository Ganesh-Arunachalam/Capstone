# ---------------------------------------------------------------------------
# Network Security Group
# ---------------------------------------------------------------------------
resource "azurerm_network_security_group" "main" {
  name                = var.nsg_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# NSG Rules — each rule is created from the nsg_rules input list
# ---------------------------------------------------------------------------
resource "azurerm_network_security_rule" "rules" {
  for_each = { for rule in var.nsg_rules : rule.name => rule }

  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
}
