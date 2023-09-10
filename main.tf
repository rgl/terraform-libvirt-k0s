# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.5.7"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    # see https://registry.terraform.io/providers/hashicorp/template
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
    # see https://registry.terraform.io/providers/alessiodionisi/k0s
    # see https://github.com/alessiodionisi/terraform-provider-k0s
    k0s = {
      source  = "alessiodionisi/k0s"
      version = "0.2.1"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "prefix" {
  type    = string
  default = "k0s"
}

variable "controller_count" {
  type    = number
  default = 1
  validation {
    condition     = var.controller_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "worker_count" {
  type    = number
  default = 2
  validation {
    condition     = var.worker_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "cluster_name" {
  description = "A name to provide for the k0s cluster"
  type        = string
  default     = "k0s"
}

locals {
  controller_nodes = [
    for i in range(var.controller_count) : {
      name    = "c${i}"
      address = "10.17.3.${10 + i}"
    }
  ]
  worker_nodes = [
    for i in range(var.worker_count) : {
      name    = "w${i}"
      address = "10.17.3.${20 + i}"
    }
  ]
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/network.markdown
resource "libvirt_network" "k0s" {
  name      = var.prefix
  mode      = "nat"
  domain    = "${var.cluster_name}.test"
  addresses = ["10.17.3.0/24"]
  dhcp {
    enabled = false
  }
  dns {
    enabled    = true
    local_only = false
  }
}

# create a cloud-init cloud-config.
# NB this creates an iso image that will be used by the NoCloud cloud-init datasource.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/cloudinit.html.markdown
# see journactl -u cloud-init
# see /run/cloud-init/*.log
# see https://cloudinit.readthedocs.io/en/latest/topics/examples.html#disk-setup
# see https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html#datasource-nocloud
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/libvirt/cloudinit_def.go#L133-L162
resource "libvirt_cloudinit_disk" "controller" {
  count     = var.controller_count
  name      = "${var.prefix}_${local.controller_nodes[count.index].name}_cloudinit.iso"
  user_data = <<EOF
#cloud-config
fqdn: ${local.controller_nodes[count.index].name}.${libvirt_network.k0s.domain}
manage_etc_hosts: true
users:
  - name: vagrant
    passwd: '$6$rounds=4096$NQ.EmIrGxn$rTvGsI3WIsix9TjWaDfKrt9tm3aa7SX7pzB.PSjbwtLbsplk1HsVzIrZbXwQNce6wmeJXhCq9YFJHDx9bXFHH.'
    lock_passwd: false
    ssh-authorized-keys:
      - ${jsonencode(trimspace(file("~/.ssh/id_rsa.pub")))}
runcmd:
  - sed -i '/vagrant insecure public key/d' /home/vagrant/.ssh/authorized_keys
EOF
}

resource "libvirt_cloudinit_disk" "worker" {
  count     = var.worker_count
  name      = "${var.prefix}_${local.worker_nodes[count.index].name}_cloudinit.iso"
  user_data = <<EOF
#cloud-config
fqdn: ${local.worker_nodes[count.index].name}.${libvirt_network.k0s.domain}
manage_etc_hosts: true
users:
  - name: vagrant
    passwd: '$6$rounds=4096$NQ.EmIrGxn$rTvGsI3WIsix9TjWaDfKrt9tm3aa7SX7pzB.PSjbwtLbsplk1HsVzIrZbXwQNce6wmeJXhCq9YFJHDx9bXFHH.'
    lock_passwd: false
    ssh-authorized-keys:
      - ${jsonencode(trimspace(file("~/.ssh/id_rsa.pub")))}
runcmd:
  - sed -i '/vagrant insecure public key/d' /home/vagrant/.ssh/authorized_keys
EOF
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/volume.html.markdown
resource "libvirt_volume" "controller" {
  count            = var.controller_count
  name             = "${var.prefix}_c${count.index}.img"
  base_volume_name = "debian-12-amd64_vagrant_box_image_0.0.0_box.img"
  format           = "qcow2"
  size             = 40 * 1024 * 1024 * 1024 # 40GiB.
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/volume.html.markdown
resource "libvirt_volume" "worker" {
  count            = var.worker_count
  name             = "${var.prefix}_w${count.index}.img"
  base_volume_name = "debian-12-amd64_vagrant_box_image_0.0.0_box.img"
  format           = "qcow2"
  size             = 40 * 1024 * 1024 * 1024 # 40GiB.
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/domain.html.markdown
resource "libvirt_domain" "controller" {
  count   = var.controller_count
  name    = "${var.prefix}_${local.controller_nodes[count.index].name}"
  machine = "q35"
  cpu {
    mode = "host-passthrough"
  }
  vcpu       = 4
  memory     = 2 * 1024
  qemu_agent = true
  cloudinit  = libvirt_cloudinit_disk.controller[count.index].id
  xml {
    xslt = file("libvirt-domain.xsl")
  }
  video {
    type = "qxl"
  }
  disk {
    volume_id = libvirt_volume.controller[count.index].id
    scsi      = true
  }
  network_interface {
    network_id     = libvirt_network.k0s.id
    wait_for_lease = true
    addresses      = [local.controller_nodes[count.index].address]
  }
  provisioner "remote-exec" {
    inline = [
      <<-EOF
      set -x
      cloud-init status --long --wait
      EOF
    ]
    connection {
      type        = "ssh"
      user        = "vagrant"
      host        = self.network_interface[0].addresses[0] # see https://github.com/dmacvicar/terraform-provider-libvirt/issues/660
      private_key = file("~/.ssh/id_rsa")
    }
  }
  lifecycle {
    ignore_changes = [
      disk[0].wwn,
    ]
  }
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.7.1/website/docs/r/domain.html.markdown
resource "libvirt_domain" "worker" {
  count   = var.worker_count
  name    = "${var.prefix}_${local.worker_nodes[count.index].name}"
  machine = "q35"
  cpu {
    mode = "host-passthrough"
  }
  vcpu       = 4
  memory     = 2 * 1024
  qemu_agent = true
  cloudinit  = libvirt_cloudinit_disk.worker[count.index].id
  xml {
    xslt = file("libvirt-domain.xsl")
  }
  video {
    type = "qxl"
  }
  disk {
    volume_id = libvirt_volume.worker[count.index].id
    scsi      = true
  }
  network_interface {
    network_id     = libvirt_network.k0s.id
    wait_for_lease = true
    addresses      = [local.worker_nodes[count.index].address]
  }
  provisioner "remote-exec" {
    inline = [
      <<-EOF
      set -x
      cloud-init status --long --wait
      EOF
    ]
    connection {
      type        = "ssh"
      user        = "vagrant"
      host        = self.network_interface[0].addresses[0] # see https://github.com/dmacvicar/terraform-provider-libvirt/issues/660
      private_key = file("~/.ssh/id_rsa")
    }
  }
  lifecycle {
    ignore_changes = [
      disk[0].wwn,
    ]
  }
}

resource "k0s_cluster" "k0s" {
  name    = var.cluster_name
  version = "v1.26.8+k0s.0" # see https://github.com/k0sproject/k0s/releases
  depends_on = [
    libvirt_domain.controller,
    libvirt_domain.worker,
  ]
  hosts = concat(
    [
      for n in local.controller_nodes : {
        role = "controller+worker"
        ssh = {
          address  = n.address
          port     = 22
          user     = "vagrant"
          key_path = "~/.ssh/id_rsa"
        }
      }
    ],
    [
      for n in local.worker_nodes : {
        role = "worker"
        ssh = {
          address  = n.address
          port     = 22
          user     = "vagrant"
          key_path = "~/.ssh/id_rsa"
        }
      }
    ]
  )
  config = yamlencode({
    spec = {
      telemetry = {
        enabled = false
      }
    }
  })
}

output "kubeconfig" {
  sensitive = true
  value     = k0s_cluster.k0s.kubeconfig
}

output "controllers" {
  value = [for node in local.controller_nodes : node.address]
}

output "workers" {
  value = [for node in local.worker_nodes : node.address]
}
