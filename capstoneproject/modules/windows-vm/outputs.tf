output "vm_id" {
  description = "Resource ID of the Virtual Machine."
  value       = azurerm_windows_virtual_machine.main.id
}

output "vm_name" {
  description = "Azure resource name of the Virtual Machine."
  value       = azurerm_windows_virtual_machine.main.name
}

output "public_ip_address" {
  description = "Public IP address allocated to the VM."
  value       = azurerm_public_ip.main.ip_address
}

output "private_ip_address" {
  description = "Private IP address assigned to the NIC."
  value       = azurerm_network_interface.main.private_ip_address
}

output "nic_id" {
  description = "Resource ID of the Network Interface."
  value       = azurerm_network_interface.main.id
}

output "pip_id" {
  description = "Resource ID of the Public IP address."
  value       = azurerm_public_ip.main.id
}
