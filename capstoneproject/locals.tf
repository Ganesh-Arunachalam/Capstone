# ---------------------------------------------------------------------------
# Naming convention: <type>-<role>-<project>-<env>-<region>
# All derived resource names are centralized here to ensure consistency.
# ---------------------------------------------------------------------------
locals {
  name_prefix = "${var.project}-${var.environment}"

  # Resource Group
  resource_group_name = "rg-${local.name_prefix}-${var.location}"

  # Networking
  vnet_name   = "vnet-${local.name_prefix}-${var.location}"
  subnet_name = "snet-${local.name_prefix}-${var.location}"

  # Network Security Groups
  web_nsg_name     = "nsg-web-${local.name_prefix}"
  monitor_nsg_name = "nsg-mon-${local.name_prefix}"

  # Web Server (VM01) resources
  web_vm_name       = "vm-web01-${local.name_prefix}"
  web_computer_name = "WEB01"                        # Windows NetBIOS hostname (max 15 chars)
  web_nic_name      = "nic-web01-${local.name_prefix}"
  web_pip_name      = "pip-web01-${local.name_prefix}"

  # Monitor Server (VM02) resources
  monitor_vm_name       = "vm-mon01-${local.name_prefix}"
  monitor_computer_name = "MON01"                    # Windows NetBIOS hostname (max 15 chars)
  monitor_nic_name      = "nic-mon01-${local.name_prefix}"
  monitor_pip_name      = "pip-mon01-${local.name_prefix}"

  # Default tags applied to every resource
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}
