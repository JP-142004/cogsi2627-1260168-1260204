output "db_vm" {
  description = "Database VM details"
  value = {
    name    = libvirt_domain.db.name
    ip      = libvirt_domain.db.network_interface[0].addresses[0]
    port    = 9092
  }
}

output "app_vm" {
  description = "Application VM details"
  value = {
    name    = libvirt_domain.app.name
    ip      = libvirt_domain.app.network_interface[0].addresses[0]
    port    = 8080
  }
}

output "proxy_vm" {
  description = "Proxy VM details"
  value = {
    name    = libvirt_domain.proxy.name
    ip      = libvirt_domain.proxy.network_interface[0].addresses[0]
    port    = 80
  }
}

output "network" {
  description = "Network configuration"
  value = {
    name       = libvirt_network.ca2.name
    cidr       = "192.168.56.0/24"
    mode       = "nat"
  }
}

output "connection_strings" {
  description = "How to connect to services"
  value = {
    h2_database = "tcp://192.168.56.30:9092"
    bookstore   = "http://192.168.56.10:8080"
    nginx_proxy = "http://192.168.56.20:80"
  }
}
