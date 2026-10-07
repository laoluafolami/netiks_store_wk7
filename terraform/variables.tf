variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "netiks-store-rg2"
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  default     = "centralus"
}

variable "vm_size" {
  description = "Size of the Virtual Machine"
  type        = string
  default     = "Standard_B2s"
}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Address prefix for the Subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "admin_public_key" {
  description = "Your SSH public key for secure VM access"
  type        = string
}

variable "allowed_ssh_ips" {
  description = "List of IP addresses/CIDR blocks allowed to SSH. CHANGE THIS FROM 0.0.0.0/0 TO YOUR SPECIFIC IP (e.g., ['203.0.113.5/32'])"
  type        = list(string)
  default     = ["105.127.11.79/32"] # WARNING: Update this before applying!
}