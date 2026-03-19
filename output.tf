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
output "dns_forward" {
  value = (
    local.dns_provider == "opnsense" ? opnsense_unbound_host_override.forward[0] :
    local.dns_provider == "rfc2136" ? dns_a_record_set.forward[0] :
    null
  )
  description = "Forward DNS record resource (null if DNS disabled)"
}
