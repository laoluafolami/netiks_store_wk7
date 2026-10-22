output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = pathexpand(var.kubeconfig_path)
}

output "cluster_name" {
  description = "Name of the kind cluster"
  value       = kind_cluster.netiks.name
}