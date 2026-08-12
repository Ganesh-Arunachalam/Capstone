# Azure Resource Manager provider configuration
provider "azurerm" {
  features {
    resource_group {
      # Allows destroy even when child resources exist (useful for dev/test teardown)
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      # Automatically remove the OS disk when the VM is deleted
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }
}
