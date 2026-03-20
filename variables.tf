variable "defaults" {
  description = "Default values for parameters. Explicit parameter values take precedence."
  type = object({
    cluster_name                     = optional(string)
    node_name                        = optional(string)
    vm_os                            = optional(string)
    clone_vm_id                      = optional(number)
    clone_vm_ids                     = optional(map(number))
    clone_node_name                  = optional(string)
    initialization_datastore_id      = optional(string)
    initialization_dns_domain        = optional(string)
    initialization_dns_servers       = optional(list(string))
    initialization_ipv4_gateway      = optional(string)
    initialization_user_data_file_id = optional(string)
    enable_netbox                    = optional(bool)
    prevent_destroy                  = optional(bool)
    dns_provider                     = optional(string)
    dns_zone                         = optional(string)
    dns_ttl                          = optional(number)
  })
  default = {}
}

variable "cluster_name" {
  type        = string
  description = "Proxmox cluster name"
  default     = null
}

variable "vm_name" {
  type        = string
  description = "Virtual machine name"
}

variable "node_name" {
  type        = string
  description = "Proxmox node name"
  default     = null
}

variable "vm_id" {
  type        = number
  description = "Virtual machine ID"
}

variable "vm_os" {
  type        = string
  description = "Operating system identifier (e.g. debian13), used for tagging and clone_vm_ids lookup"
  default     = null
}

variable "memory_size" {
  type        = number
  description = "RAM size in MB"
  default     = 1024
}

variable "cpu_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 1
}

variable "cpu_type" {
  type        = string
  description = "CPU type"
  default     = "host"
}

variable "clone_vm_id" {
  type        = number
  description = "Template VM ID to clone from. If null, resolved from defaults.clone_vm_ids[vm_os]."
  default     = null
}

variable "clone_node_name" {
  type        = string
  description = "Node where the template resides. Defaults to node_name if not set."
  default     = null
}

variable "network_interfaces" {
  type = list(object({
    bridge       = string
    model        = optional(string, "virtio")
    firewall     = optional(bool, false)
    vlan_id      = optional(number)
    ipv4_address = optional(string)
    ipv6_address = optional(string)
  }))
  description = "Network interfaces"
}

variable "disks" {
  type = list(object({
    datastore_id      = optional(string)
    interface         = optional(string)
    size              = optional(number)
    file_format       = optional(string, "raw")
    iothread          = optional(bool, true)
    serial            = optional(string)
    path_in_datastore = optional(string)
    backup            = optional(bool)
  }))
  description = "Disks. For passthrough: set path_in_datastore to host device path, file_format to raw."
}

variable "initialization_datastore_id" {
  type        = string
  description = "Datastore for cloud-init drive"
  default     = null
}

variable "initialization_dns_domain" {
  type        = string
  description = "DNS domain for cloud-init"
  default     = null
}

variable "initialization_dns_servers" {
  type        = list(string)
  description = "DNS servers for cloud-init"
  default     = null
}

variable "initialization_ipv4_gateway" {
  type        = string
  description = "IPv4 gateway for cloud-init"
  default     = null
}

variable "initialization_user_data_file_id" {
  type        = string
  description = "Cloud-init user data file ID"
  default     = null
}

variable "enable_netbox" {
  type        = bool
  description = "Whether to create Netbox resources"
  default     = null
}

variable "provisioner_extra_commands" {
  type        = list(string)
  description = "Additional shell commands to run via remote-exec after VM creation"
  default     = []
}

variable "skip_clone" {
  type        = bool
  description = "Skip clone, cloud-init and provisioning. Use for VMs created from ISO."
  default     = false
}

variable "started" {
  type        = bool
  description = "Start the VM after creation. Set to false for ISO installs (avoids 15min agent timeout)."
  default     = true
}

variable "cdrom" {
  type = object({
    file_id   = string
    interface = optional(string, "ide2")
  })
  description = "CD-ROM/ISO configuration. Set file_id to 'none' after install."
  default     = null
}

variable "boot_order" {
  type        = list(string)
  description = "Boot device order, e.g. [\"scsi0\", \"ide2\", \"net0\"]"
  default     = null
}

variable "scsi_hardware" {
  type        = string
  description = "SCSI hardware type (e.g. virtio-scsi-single, virtio-scsi-pci)"
  default     = null
}

variable "prevent_destroy" {
  type        = bool
  description = "Prevent accidental VM deletion. When true, any plan that would destroy the VM (including force-replacement) will be rejected."
  default     = null
}

variable "dns_provider" {
  type        = string
  description = "DNS provider: 'opnsense', 'rfc2136', or null to disable. Use 'rfc2136' for PowerDNS, Bind, Knot, etc."
  default     = null
  validation {
    condition     = var.dns_provider == null || contains(["opnsense", "rfc2136"], var.dns_provider)
    error_message = "dns_provider must be 'opnsense', 'rfc2136', or null"
  }
}

variable "dns_zone" {
  type        = string
  description = "DNS zone with trailing dot, e.g. 'sciborek.com.' (RFC2136). Derived from vm_name if null."
  default     = null
}

variable "dns_ttl" {
  type        = number
  description = "DNS record TTL in seconds (RFC2136, default 3600)"
  default     = null
}

