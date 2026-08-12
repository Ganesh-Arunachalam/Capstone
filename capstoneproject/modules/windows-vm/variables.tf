variable "resource_group_name" {
  description = "Name of the Resource Group in which to create VM resources."
  type        = string
}

variable "location" {
  description = "Azure region for VM resources."
  type        = string
}

variable "vm_name" {
  description = "Azure resource name for the Virtual Machine (up to 64 characters)."
  type        = string
}

variable "computer_name" {
  description = "Windows hostname for the VM (max 15 characters — NetBIOS limit)."
  type        = string
}

variable "vm_size" {
  description = "Azure VM SKU (e.g. Standard_B2s, Standard_D2s_v3)."
  type        = string
}

variable "admin_username" {
  description = "Administrator username for the Windows VM."
  type        = string
}

variable "admin_password" {
  description = "Administrator password for the Windows VM. Must meet Azure complexity requirements."
  type        = string
  sensitive   = true
}

variable "subnet_id" {
  description = "Resource ID of the Subnet to which the NIC will be attached."
  type        = string
}

variable "nsg_id" {
  description = "Resource ID of the NSG to associate with the NIC."
  type        = string
}

variable "nic_name" {
  description = "Name for the Network Interface resource."
  type        = string
}

variable "pip_name" {
  description = "Name for the Public IP address resource."
  type        = string
}

variable "os_disk_type" {
  description = "OS disk managed disk storage tier (Standard_LRS | StandardSSD_LRS | Premium_LRS)."
  type        = string
  default     = "StandardSSD_LRS"
}

variable "tags" {
  description = "Tags to apply to all VM resources."
  type        = map(string)
  default     = {}
}
