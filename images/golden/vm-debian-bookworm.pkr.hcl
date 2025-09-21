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
variable "iso_storage" {}
variable "ssh_public_key" {}
variable "ssh_private_key" {}

source "proxmox-virtual_environment" "vm" {
  proxmox_url  = var.proxmox_url
  username     = var.proxmox_username
  token        = var.proxmox_token
  node         = var.proxmox_node
  vm_id        = 9100
  name         = "ralf-vm-debian-bookworm"
  qemu_os      = "l26"
  cores        = 4
  sockets      = 1
  memory       = 4096
  scsi_controller = "virtio-scsi-single"
  disk {
    datastore_id = var.storage_pool
    size         = "40G"
    type         = "scsi"
  }
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }
  cdrom {
    datastore_id = var.iso_storage
    file_id      = "local:iso/debian-12.5.0-amd64-netinst.iso"
  }
  efi_disk {
    datastore_id = var.storage_pool
  }
  cloud_init {
    user_data_file_id = "local:snippets/debian-cloudinit.yaml"
  }
  ssh_username    = "admin"
  ssh_private_key = var.ssh_private_key
}

build {
  name    = "ralf-vm-bookworm"
  sources = ["source.proxmox-virtual_environment.vm"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y",
      "sudo systemctl enable --now unattended-upgrades"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo useradd -m -s /bin/bash ralf",
      "echo '${var.ssh_public_key}' | sudo tee /home/ralf/.ssh/authorized_keys",
      "sudo chown -R ralf:ralf /home/ralf/.ssh",
      "sudo chmod 600 /home/ralf/.ssh/authorized_keys"
    ]
  }
}
