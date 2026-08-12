# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
output "resource_group_name" {
  description = "Name of the deployed Resource Group."
  value       = azurerm_resource_group.main.name
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
output "vnet_name" {
  description = "Name of the Virtual Network."
  value       = module.networking.vnet_name
}

output "subnet_name" {
  description = "Name of the default Subnet."
  value       = module.networking.subnet_name
}

# ---------------------------------------------------------------------------
# Web Server (VM01)
# ---------------------------------------------------------------------------
output "web_vm_name" {
  description = "Azure resource name of the Web Server VM."
  value       = module.vm_web.vm_name
}

output "web_vm_public_ip" {
  description = "Public IP address of the Web Server (HTTP/HTTPS/RDP)."
  value       = module.vm_web.public_ip_address
}

output "web_vm_private_ip" {
  description = "Private IP address of the Web Server."
  value       = module.vm_web.private_ip_address
}

# ---------------------------------------------------------------------------
# Monitor Server (VM02)
# ---------------------------------------------------------------------------
output "monitor_vm_name" {
  description = "Azure resource name of the Monitor Server VM."
  value       = module.vm_monitor.vm_name
}

output "monitor_vm_public_ip" {
  description = "Public IP address of the Monitor Server (RDP)."
  value       = module.vm_monitor.public_ip_address
}

output "monitor_vm_private_ip" {
  description = "Private IP address of the Monitor Server."
  value       = module.vm_monitor.private_ip_address
}
