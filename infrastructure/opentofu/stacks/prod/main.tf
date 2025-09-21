module "toolchain" {
  source             = "../../modules/toolchain"
  environment        = "prod"
  container_registry = "registry.prod.homelab.lan"
}
