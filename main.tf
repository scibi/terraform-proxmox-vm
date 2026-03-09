terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.98.1"
    }
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.1.0"
    }
  }
}

locals {
  cluster_name                     = var.cluster_name != null ? var.cluster_name : var.defaults.cluster_name
  node_name                        = var.node_name != null ? var.node_name : var.defaults.node_name
  vm_os                            = var.vm_os != null ? var.vm_os : var.defaults.vm_os
  clone_vm_id                      = var.clone_vm_id != null ? var.clone_vm_id : try(var.defaults.clone_vm_ids[local.vm_os], var.defaults.clone_vm_id)
  clone_node_name                  = var.clone_node_name != null ? var.clone_node_name : try(var.defaults.clone_node_name, local.node_name)
  enable_netbox                    = var.enable_netbox != null ? var.enable_netbox : try(var.defaults.enable_netbox, true)
  initialization_datastore_id      = var.initialization_datastore_id != null ? var.initialization_datastore_id : var.defaults.initialization_datastore_id
  initialization_dns_domain        = var.initialization_dns_domain != null ? var.initialization_dns_domain : var.defaults.initialization_dns_domain
  initialization_dns_servers       = var.initialization_dns_servers != null ? var.initialization_dns_servers : var.defaults.initialization_dns_servers
  initialization_ipv4_gateway      = var.initialization_ipv4_gateway != null ? var.initialization_ipv4_gateway : var.defaults.initialization_ipv4_gateway
  initialization_user_data_file_id = var.initialization_user_data_file_id != null ? var.initialization_user_data_file_id : var.defaults.initialization_user_data_file_id
}

data "netbox_cluster" "cluster" {
  count = local.enable_netbox ? 1 : 0
  name  = local.cluster_name
}

data "netbox_tag" "terraform" {
  count = local.enable_netbox ? 1 : 0
  name  = "Terraform"
}

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.vm_name
  description = "Managed by Terraform"
  tags        = ["terraform", local.vm_os]

  connection {
    type = "ssh"
    user = "root"
    host = self.name
  }

  provisioner "remote-exec" {
    inline = concat([
      "echo '${split("/", self.initialization[0].ip_config[0].ipv4[0].address)[0]} ${self.name} ${split(".", self.name)[0]}' >> /etc/hosts",
      "sed -i '/^127\\.0\\.1\\.1\\s/d' /etc/hosts",
      "hostnamectl set-hostname ${split(".", self.name)[0]}",
    ], var.provisioner_extra_commands)
  }

  node_name = local.node_name
  vm_id     = var.vm_id

  memory {
    dedicated = var.memory_size
  }

  cpu {
    cores = var.cpu_cores
    type  = var.cpu_type
  }

  clone {
    vm_id     = local.clone_vm_id
    node_name = local.clone_node_name
  }

  agent {
    enabled = true
  }

  startup {
    order      = "3"
    up_delay   = "60"
    down_delay = "60"
  }

  dynamic "network_device" {
    for_each = var.network_interfaces
    content {
      bridge   = network_device.value.bridge
      model    = network_device.value.model
      firewall = network_device.value.firewall
      vlan_id  = network_device.value.vlan_id
    }
  }

  dynamic "disk" {
    for_each = var.disks
    content {
      datastore_id = coalesce(disk.value.datastore_id, local.initialization_datastore_id)
      interface    = coalesce(disk.value.interface, "scsi${disk.key}")
      size         = disk.value.size
      file_format  = disk.value.file_format
      iothread     = disk.value.iothread
    }
  }

  initialization {
    datastore_id = local.initialization_datastore_id
    dns {
      domain  = local.initialization_dns_domain
      servers = local.initialization_dns_servers
    }
    ip_config {
      ipv4 {
        address = var.network_interfaces[0].ipv4_address
        gateway = local.initialization_ipv4_gateway
      }
    }
    user_data_file_id = local.initialization_user_data_file_id
  }

  vga {
    memory = 4
  }

  reboot_after_update = false

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_data_file_id,
      clone[0].node_name,
    ]
  }
}

resource "netbox_virtual_machine" "vm" {
  count = local.enable_netbox ? 1 : 0

  cluster_id = data.netbox_cluster.cluster[0].id
  site_id    = data.netbox_cluster.cluster[0].site_id

  name         = proxmox_virtual_environment_vm.vm.name
  memory_mb    = proxmox_virtual_environment_vm.vm.memory[0].dedicated
  disk_size_mb = sum([for d in var.disks : d.size]) * 1024

  vcpus = var.cpu_cores
  local_context_data = jsonencode({
    "vm_id" = proxmox_virtual_environment_vm.vm.id
  })
  tags       = [data.netbox_tag.terraform[0].name]
  depends_on = [proxmox_virtual_environment_vm.vm]
}

locals {
  interfaces = {
    for i, iface in var.network_interfaces :
    i => {
      "idx"            = i
      "conf"           = iface
      "iface"          = proxmox_virtual_environment_vm.vm.network_interface_names[i + 1]
      "mac_address"    = proxmox_virtual_environment_vm.vm.mac_addresses[i + 1]
      "ipv4_addresses" = proxmox_virtual_environment_vm.vm.ipv4_addresses[i + 1]
      "ipv6_addresses" = proxmox_virtual_environment_vm.vm.ipv6_addresses[i + 1]
      "network_device" = proxmox_virtual_environment_vm.vm.network_device[i] # W network_devices nie ma interfejsu lo
    }
  }
  disks = {
    for i, disk in var.disks :
    proxmox_virtual_environment_vm.vm.disk[i].interface => {
      "idx"  = i
      "conf" = disk
      "disk" = proxmox_virtual_environment_vm.vm.disk[i]
    }
  }
}

resource "netbox_interface" "iface" {
  for_each = local.enable_netbox ? local.interfaces : {}

  virtual_machine_id = netbox_virtual_machine.vm[0].id
  name               = each.value.iface
  enabled            = each.value.network_device.enabled
  mac_address        = each.value.mac_address
  tags               = [data.netbox_tag.terraform[0].name]
  depends_on         = [netbox_virtual_machine.vm]
}

resource "netbox_ip_address" "ipv4" {
  for_each = local.enable_netbox ? { for k, v in local.interfaces : k => v if v.conf.ipv4_address != null } : {}

  ip_address                   = each.value.conf.ipv4_address
  status                       = "active"
  virtual_machine_interface_id = netbox_interface.iface[each.key].id
  dns_name                     = each.value.iface == "eth0" ? var.vm_name : null
  description                  = "${var.vm_name} (${each.value.iface})"
  tags                         = [data.netbox_tag.terraform[0].name]
}

resource "netbox_primary_ip" "primary_ip4" {
  count = local.enable_netbox ? 1 : 0

  ip_address_id      = netbox_ip_address.ipv4["0"].id
  virtual_machine_id = netbox_virtual_machine.vm[0].id
}

resource "netbox_virtual_disk" "disk" {
  for_each = local.enable_netbox ? local.disks : {}

  name               = each.value.disk.interface
  description        = each.value.disk.path_in_datastore
  size_mb            = each.value.disk.size * 1024
  virtual_machine_id = netbox_virtual_machine.vm[0].id
  tags               = [data.netbox_tag.terraform[0].name]
}
