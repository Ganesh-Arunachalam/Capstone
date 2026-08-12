# ---------------------------------------------------------------------------
# Resource Group — container for all project resources
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ---------------------------------------------------------------------------
# Networking: Virtual Network + Subnet
# ---------------------------------------------------------------------------
module "networking" {
  source = "./modules/networking"

  resource_group_name   = azurerm_resource_group.main.name
  location              = azurerm_resource_group.main.location
  vnet_name             = local.vnet_name
  vnet_address_space    = var.vnet_address_space
  subnet_name           = local.subnet_name
  subnet_address_prefix = var.subnet_address_prefix
  tags                  = local.common_tags
}

# ---------------------------------------------------------------------------
# Security: NSG for Web Server — HTTP, HTTPS, and RDP inbound
# ---------------------------------------------------------------------------
module "security_web" {
  source = "./modules/security"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  nsg_name            = local.web_nsg_name
  tags                = local.common_tags

  nsg_rules = [
    {
      name                       = "Allow-HTTP-Inbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
    {
      name                       = "Allow-HTTPS-Inbound"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
    {
      name                       = "Allow-RDP-Inbound"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
  ]
}

# ---------------------------------------------------------------------------
# Security: NSG for Monitor Server — RDP inbound only
# ---------------------------------------------------------------------------
module "security_monitor" {
  source = "./modules/security"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  nsg_name            = local.monitor_nsg_name
  tags                = local.common_tags

  nsg_rules = [
    {
      name                       = "Allow-RDP-Inbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    },
  ]
}

# ---------------------------------------------------------------------------
# VM01: Web Server
# ---------------------------------------------------------------------------
module "vm_web" {
  source = "./modules/windows-vm"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  vm_name             = local.web_vm_name
  computer_name       = local.web_computer_name
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  subnet_id           = module.networking.subnet_id
  nsg_id              = module.security_web.nsg_id
  nic_name            = local.web_nic_name
  pip_name            = local.web_pip_name
  os_disk_type        = var.os_disk_type
  tags                = local.common_tags
}

# ---------------------------------------------------------------------------
# VM02: Monitor Server
# ---------------------------------------------------------------------------
module "vm_monitor" {
  source = "./modules/windows-vm"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  vm_name             = local.monitor_vm_name
  computer_name       = local.monitor_computer_name
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  subnet_id           = module.networking.subnet_id
  nsg_id              = module.security_monitor.nsg_id
  nic_name            = local.monitor_nic_name
  pip_name            = local.monitor_pip_name
  os_disk_type        = var.os_disk_type
  tags                = local.common_tags
}
