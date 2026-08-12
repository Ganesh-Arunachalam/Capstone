variable "resource_group_name" {
  description = "Name of the Resource Group in which to create networking resources."
  type        = string
}

variable "location" {
  description = "Azure region for networking resources."
  type        = string
}

variable "vnet_name" {
  description = "Name of the Virtual Network."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network (list of CIDR blocks)."
  type        = list(string)
}

variable "subnet_name" {
  description = "Name of the Subnet."
  type        = string
}

variable "subnet_address_prefix" {
  description = "Address prefix for the Subnet (CIDR notation)."
  type        = string
}

variable "tags" {
  description = "Tags to apply to networking resources."
  type        = map(string)
  default     = {}
}
