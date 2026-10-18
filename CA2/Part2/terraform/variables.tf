variable "vms" {
  description = "VM configuration"
  type = map(object({
    memory = number
    cpus   = number
  }))
  default = {
    db = {
      memory = 1024   # 1GB
      cpus   = 1
    }
    app = {
      memory = 2048   # 2GB
      cpus   = 2
    }
    proxy = {
      memory = 512    # 512MB
      cpus   = 1
    }
  }
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioning"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for cloud-init"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "storage_pool_path" {
  description = "Path for libvirt storage pool"
  type        = string
  default     = "/var/lib/libvirt/ca2-pool"
}
