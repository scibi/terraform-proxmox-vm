output "vm" {
  value = {
    id                      = proxmox_virtual_environment_vm.vm.id
    vm_id                   = proxmox_virtual_environment_vm.vm.vm_id
    name                    = proxmox_virtual_environment_vm.vm.name
    node_name               = proxmox_virtual_environment_vm.vm.node_name
    ipv4_addresses          = proxmox_virtual_environment_vm.vm.ipv4_addresses
    ipv6_addresses          = proxmox_virtual_environment_vm.vm.ipv6_addresses
    mac_addresses           = proxmox_virtual_environment_vm.vm.mac_addresses
    network_interface_names = proxmox_virtual_environment_vm.vm.network_interface_names
  }
  description = "Selected attributes of the Proxmox VM resource"
}
output "netbox_vm" {
  value       = local.enable_netbox ? netbox_virtual_machine.vm[0] : null
  description = "The Netbox virtual machine resource (null if Netbox disabled)"
}
output "ifaces" {
  value       = local.interfaces
  description = "Map of network interfaces with runtime data"
}
output "disks" {
  value       = local.disks
  description = "Map of disks with runtime data"
}
output "dns_forward" {
  value = (
    local.dns_provider == "opnsense" ? opnsense_unbound_host_override.forward[0] :
    local.dns_provider == "rfc2136" ? dns_a_record_set.forward[0] :
    null
  )
  description = "Forward DNS record resource (null if DNS disabled)"
}
