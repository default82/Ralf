variable "environment" {
  type        = string
  description = "Environment name for the toolchain stack"
}

variable "container_registry" {
  type        = string
  description = "Registry endpoint used by CI/CD tools"
}

variable "additional_services" {
  type        = list(string)
  description = "Optional additional services to document in the manifest"
  default     = []
}
