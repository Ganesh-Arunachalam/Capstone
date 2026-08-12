output "vnet_id" {
  description = "Resource ID of the Virtual Network."
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network."
  value       = azurerm_virtual_network.main.name
}

output "subnet_id" {
  description = "Resource ID of the Subnet."
  value       = azurerm_subnet.main.id
}

output "subnet_name" {
  description = "Name of the Subnet."
  value       = azurerm_subnet.main.name
}
