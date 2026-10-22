terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

provider "kubernetes" {
  config_path = pathexpand("~/.kube/netiks.config")
}

resource "kubernetes_namespace" "environments" {
  for_each = var.environments

  metadata {
    name = each.key
  }
}

resource "kubernetes_resource_quota" "environment_quotas" {
  for_each = var.environments

  metadata {
    name      = "${each.key}-quota"
    namespace = kubernetes_namespace.environments[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = each.value.cpu_requests
      "requests.memory" = each.value.memory_requests
      "limits.memory"   = each.value.memory_limits
      "pods"            = each.value.max_pods
    }
  }
}