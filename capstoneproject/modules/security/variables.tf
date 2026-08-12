variable "resource_group_name" {
  description = "Name of the Resource Group in which to create the NSG."
  type        = string
}

variable "location" {
  description = "Azure region for the NSG."
  type        = string
}

variable "nsg_name" {
  description = "Name of the Network Security Group."
  type        = string
}

variable "nsg_rules" {
  description = "List of NSG rules (inbound or outbound) to create on the NSG."
  type = list(object({
    name                       = string
    priority                   = number
    direction                  = string  # Inbound | Outbound
    access                     = string  # Allow | Deny
    protocol                   = string  # Tcp | Udp | Icmp | *
    source_port_range          = string
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = string
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to the NSG."
  type        = map(string)
  default     = {}
}
