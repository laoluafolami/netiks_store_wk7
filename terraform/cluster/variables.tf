variable "cluster_name" {
  description = "Name of the kind cluster"
  type        = string
  default     = "netiks"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/netiks.config"
}