variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "subnet_id" { type = string }
variable "vm_size" { type = string }
variable "admin_username" { type = string }
variable "admin_public_key" { type = string }
variable "acr_login_server" { type = string }

resource "azurerm_public_ip" "main" {
  name                = "netiks-vm-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "main" {
  name                = "netiks-vm-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# SECURE & CORRECT: User Assigned Managed Identity for the VM
resource "azurerm_user_assigned_identity" "vm_identity" {
  name                = "netiks-vm-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# Data block to find the ACR by login server (since name has random suffix)
data "azurerm_container_registry" "acr" {
  name                = split(".", var.acr_login_server)[0]
  resource_group_name = var.resource_group_name
}

# Grant the VM identity permission to pull from ACR
resource "azurerm_role_assignment" "acr_pull" {
  scope                = data.azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.vm_identity.principal_id
}

resource "azurerm_linux_virtual_machine" "main" {
  name                = "netiks-vm"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 40
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  network_interface_ids = [azurerm_network_interface.main.id]

  # Attach the managed identity to the VM
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vm_identity.id]
  }

  # 🌟 THIS IS THE MAGIC LINE 🌟
  # It reads the bash script, encodes it in base64 (required by Azure), and passes it to the VM.
  custom_data = filebase64("${path.module}/user_data.sh")
}

output "vm_public_ip" {
  value = azurerm_public_ip.main.ip_address

 
}



