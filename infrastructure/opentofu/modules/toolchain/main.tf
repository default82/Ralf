terraform {
  required_version = ">= 1.6.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "local" {}

locals {
  default_services = [
    "gitea",
    "jenkins",
    "semaphore",
    "foreman",
    "postgresql"
  ]
}

resource "local_file" "toolchain_manifest" {
  filename = "${path.module}/toolchain-${var.environment}.txt"
  content  = <<EOT
Environment: ${var.environment}
Registry: ${var.container_registry}
%{ if length(var.additional_services) > 0 ~}
Additional services:
%{ for service in var.additional_services ~}
- ${service}
%{ endfor ~}
%{ endif ~}
Baseline stack:
%{ for service in local.default_services ~}
- ${service}
%{ endfor ~}
EOT
}
