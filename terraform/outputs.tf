# Expose the Virtual Machine's Public IP address
output "vm_public_ip" {
  description = "The public IP address of the Netiks Store VM"
  value       = module.compute.vm_public_ip
}

# Expose the Container Registry name
output "acr_name" {
  description = "The name of the Azure Container Registry"
  value       = module.registry.acr_name
}

# Expose the Container Registry login server URL
output "acr_login_server" {
  description = "The login server URL for the Azure Container Registry"
  value       = module.registry.acr_login_server
}