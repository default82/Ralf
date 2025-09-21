module "toolchain" {
  source             = "../../modules/toolchain"
  environment        = "dev"
  container_registry = "registry.dev.homelab.lan"
  additional_services = [
    "argocd",
    "harbor"
  ]
}
