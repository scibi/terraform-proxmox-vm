output "vm" {
  value       = proxmox_virtual_environment_vm.vm
  description = "The Proxmox virtual machine resource"
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
