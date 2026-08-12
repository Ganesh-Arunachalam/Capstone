# ---------------------------------------------------------------------------
# Public IP — Standard SKU, Static allocation (required for zone-redundancy
# and compatibility with Standard Load Balancers)
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "main" {
  name                = var.pip_name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Network Interface — attaches the VM to the subnet with a public IP
# ---------------------------------------------------------------------------
resource "azurerm_network_interface" "main" {
  name                = var.nic_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# ---------------------------------------------------------------------------
# NSG ↔ NIC Association — applies per-VM security rules at the NIC level
# ---------------------------------------------------------------------------
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = var.nsg_id
}

# ---------------------------------------------------------------------------
# Windows Virtual Machine
# ---------------------------------------------------------------------------
resource "azurerm_windows_virtual_machine" "main" {
  name                = var.vm_name
  computer_name       = var.computer_name  # Windows NetBIOS hostname (max 15 chars)
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = var.tags

  network_interface_ids = [azurerm_network_interface.main.id]

  os_disk {
    name                 = "osdisk-${var.vm_name}"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
  }

  # Windows Server 2022 Datacenter — latest GA Windows Server image in Azure
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  # Managed-storage boot diagnostics (no extra cost); enables serial console access
  boot_diagnostics {}
}
