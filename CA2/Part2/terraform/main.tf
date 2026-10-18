terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Criar pool de armazenamento
resource "libvirt_pool" "ca2" {
  name = "ca2-pool"
  type = "dir"
  path = "/var/lib/libvirt/ca2-pool"
}

# Criar rede privada (host-only equivalente)
resource "libvirt_network" "ca2" {
  name      = "ca2-network"
  mode      = "nat"
  addresses = ["192.168.56.0/24"]
  dhcp {
    enabled = false
  }
}

# Download da imagem Ubuntu 22.04 (Jammy)
resource "libvirt_volume" "ubuntu_image" {
  name   = "ubuntu-jammy-20241002.qcow2"
  pool   = libvirt_pool.ca2.name
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

# VM Database
resource "libvirt_volume" "db_disk" {
  name             = "ca2-db-disk.qcow2"
  pool             = libvirt_pool.ca2.name
  base_volume_id   = libvirt_volume.ubuntu_image.id
  format           = "qcow2"
  size             = 20 * 1024 * 1024 * 1024  # 20GB
}

resource "libvirt_domain" "db" {
  name   = "ca2-db"
  memory = var.vms.db.memory
  vcpu   = var.vms.db.cpus

  boot {
    dev = ["hd"]
  }

  disk {
    volume_id = libvirt_volume.db_disk.id
  }

  network_interface {
    network_id     = libvirt_network.ca2.id
    addresses      = ["192.168.56.30"]
    wait_for_lease = true
  }

  cloudinit = libvirt_cloudinit_disk.db.id

  provisioner "file" {
    source      = "${path.module}/provisioning/setup_db.sh"
    destination = "/tmp/setup_db.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path)
      host        = self.network_interface[0].addresses[0]
      timeout     = "5m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup_db.sh",
      "sudo /tmp/setup_db.sh"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path)
      host        = self.network_interface[0].addresses[0]
      timeout     = "5m"
    }
  }

  depends_on = [libvirt_network.ca2]
}

# VM App
resource "libvirt_volume" "app_disk" {
  name             = "ca2-app-disk.qcow2"
  pool             = libvirt_pool.ca2.name
  base_volume_id   = libvirt_volume.ubuntu_image.id
  format           = "qcow2"
  size             = 30 * 1024 * 1024 * 1024  # 30GB
}

resource "libvirt_domain" "app" {
  name   = "ca2-app"
  memory = var.vms.app.memory
  vcpu   = var.vms.app.cpus

  boot {
    dev = ["hd"]
  }

  disk {
    volume_id = libvirt_volume.app_disk.id
  }

  network_interface {
    network_id     = libvirt_network.ca2.id
    addresses      = ["192.168.56.10"]
    wait_for_lease = true
  }

  cloudinit = libvirt_cloudinit_disk.app.id

  provisioner "file" {
    source      = "${path.module}/provisioning/setup_app.sh"
    destination = "/tmp/setup_app.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path)
      host        = self.network_interface[0].addresses[0]
      timeout     = "10m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup_app.sh",
      "sudo /tmp/setup_app.sh"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path)
      host        = self.network_interface[0].addresses[0]
      timeout     = "10m"
    }
  }

  depends_on = [libvirt_domain.db]
}

# VM Proxy
resource "libvirt_volume" "proxy_disk" {
  name             = "ca2-proxy-disk.qcow2"
  pool             = libvirt_pool.ca2.name
  base_volume_id   = libvirt_volume.ubuntu_image.id
  format           = "qcow2"
  size             = 10 * 1024 * 1024 * 1024  # 10GB
}

resource "libvirt_domain" "proxy" {
  name   = "ca2-proxy"
  memory = var.vms.proxy.memory
  vcpu   = var.vms.proxy.cpus

  boot {
    dev = ["hd"]
  }

  disk {
    volume_id = libvirt_volume.proxy_disk.id
  }

  network_interface {
    network_id     = libvirt_network.ca2.id
    addresses      = ["192.168.56.20"]
    wait_for_lease = true
  }

  cloudinit = libvirt_cloudinit_disk.proxy.id

  provisioner "file" {
    source      = "${path.module}/provisioning/setup_proxy.sh"
    destination = "/tmp/setup_proxy.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path)
      host        = self.network_interface[0].addresses[0]
      timeout     = "5m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup_proxy.sh",
      "sudo /tmp/setup_proxy.sh"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_private_key_path)
      host        = self.network_interface[0].addresses[0]
      timeout     = "5m"
    }
  }

  depends_on = [libvirt_domain.app]
}

# Cloud-init para DB
data "template_file" "db_init" {
  template = file("${path.module}/cloud-init/db.yaml")
  vars = {
    public_key = file(var.ssh_public_key_path)
  }
}

resource "libvirt_cloudinit_disk" "db" {
  name           = "ca2-db-init.iso"
  pool           = libvirt_pool.ca2.name
  user_data      = data.template_file.db_init.rendered
  metadata       = "instance-id: ca2-db\nlocal-hostname: ca2-db"
}

# Cloud-init para App
data "template_file" "app_init" {
  template = file("${path.module}/cloud-init/app.yaml")
  vars = {
    public_key = file(var.ssh_public_key_path)
  }
}

resource "libvirt_cloudinit_disk" "app" {
  name           = "ca2-app-init.iso"
  pool           = libvirt_pool.ca2.name
  user_data      = data.template_file.app_init.rendered
  metadata       = "instance-id: ca2-app\nlocal-hostname: ca2-app"
}

# Cloud-init para Proxy
data "template_file" "proxy_init" {
  template = file("${path.module}/cloud-init/proxy.yaml")
  vars = {
    public_key = file(var.ssh_public_key_path)
  }
}

resource "libvirt_cloudinit_disk" "proxy" {
  name           = "ca2-proxy-init.iso"
  pool           = libvirt_pool.ca2.name
  user_data      = data.template_file.proxy_init.rendered
  metadata       = "instance-id: ca2-proxy\nlocal-hostname: ca2-proxy"
}
