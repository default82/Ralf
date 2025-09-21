packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {}
variable "proxmox_username" {}
variable "proxmox_token" {}
variable "proxmox_node" {}
variable "storage_pool" {}
variable "ssh_public_key" {}
variable "ssh_private_key" {}
variable "template_name" {
  default = "ralf-lxc-debian-bookworm"
}

source "proxmox-virtual_environment" "lxc" {
  proxmox_url      = var.proxmox_url
  username         = var.proxmox_username
  token            = var.proxmox_token
  insecure         = false

  template_name    = var.template_name
  node             = var.proxmox_node
  ostemplate_file  = "local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"
  storage_pool     = var.storage_pool
  unprivileged     = true

  features = ["nesting=1", "keyctl=1"]
  cores    = 2
  memory   = 2048
  password = "disabled"

  ssh_user          = "root"
  ssh_private_key   = var.ssh_private_key
  ssh_timeout       = "20m"
}

build {
  name    = "ralf-lxc-bookworm"
  sources = ["source.proxmox-virtual_environment.lxc"]

  provisioner "shell" {
    inline = [
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "systemctl enable --now unattended-upgrades"
    ]
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /root/.ssh",
      "echo '${var.ssh_public_key}' > /root/.ssh/authorized_keys",
      "chmod 600 /root/.ssh/authorized_keys"
    ]
  }
}
