terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }
  }
}

provider "kind" {}

resource "kind_cluster" "netiks" {
  name = var.cluster_name
  
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    node {
      role = "control-plane"
      extra_port_mappings {
        container_port = 30300
        host_port      = 3001
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30800
        host_port      = 8000
        protocol       = "TCP"
      }
      
    }
  }
}

resource "local_file" "kubeconfig" {
  content  = kind_cluster.netiks.kubeconfig
  filename = pathexpand(var.kubeconfig_path)
}