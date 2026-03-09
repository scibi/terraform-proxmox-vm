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
        datastore_id = optional(string)
        interface    = optional(string)
        size         = number
        file_format  = optional(string, "raw")
        iothread     = optional(bool, true)
    }))
    description = "Disks"
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
