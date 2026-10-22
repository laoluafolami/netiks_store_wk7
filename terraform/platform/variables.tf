variable "environments" {
  description = "Map of environments with their resource quotas"
  type = map(object({
    cpu_requests    = string
    memory_requests = string
    memory_limits   = string
    max_pods        = number
  }))
}