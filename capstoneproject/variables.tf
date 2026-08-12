# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "location" {
  description = "Azure region where all resources will be deployed."
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Deployment environment name (dev | test | prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, prod."
  }
}

variable "project" {
  description = "Short project name used as part of the resource naming convention."
  type        = string
  default     = "capstone"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space for the Virtual Network (CIDR notation)."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Address prefix for the default subnet (CIDR notation)."
  type        = string
  default     = "10.0.1.0/24"
}

# ---------------------------------------------------------------------------
# Virtual Machines
# ---------------------------------------------------------------------------

variable "vm_size" {
  description = "Azure VM SKU / size (e.g. Standard_B2s, Standard_D2s_v3)."
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Administrator username for both Windows VMs."
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Administrator password for both Windows VMs. Must meet Azure complexity requirements (min 12 chars, upper, lower, digit, special character)."
  type        = string
  sensitive   = true
}

variable "os_disk_type" {
  description = "OS disk managed disk storage type (Standard_LRS | StandardSSD_LRS | Premium_LRS)."
  type        = string
  default     = "StandardSSD_LRS"
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to merge with the default tag set applied to all resources."
  type        = map(string)
  default     = {}
}
