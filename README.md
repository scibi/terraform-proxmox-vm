# proxmox-vm

OpenTofu module for creating Proxmox VE virtual machines with cloud-init
initialization and optional Netbox inventory registration.

## Overview

This module:

- Clones a VM from a Proxmox template with cloud-init configuration
- Configures networking, disks, CPU, and memory
- Optionally registers the VM in Netbox (interfaces, IP addresses, disks)
- Supports a `defaults` parameter to eliminate repetition across many VMs

## Requirements

| Provider | Version |
|----------|---------|
| [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox) | ~> 0.98 |
| [e-breuninger/netbox](https://registry.terraform.io/providers/e-breuninger/netbox) | ~> 5.1 |

## Creating VM templates with Packer

This module clones VMs from Proxmox templates. A companion
[packer_debian](https://github.com/scibi/packer_debian) repository provides
Packer configuration for building cloud-init compatible Debian templates using
the [hashicorp/proxmox](https://github.com/hashicorp/packer-plugin-proxmox)
plugin (`proxmox-iso` builder).

The Packer config provides:

- Template definitions per Debian release (e.g. `debian_12_bookworm.pkr.hcl`,
  `debian_13_trixie.pkr.hcl`)
- Preseed files for fully automated installation
- Cloud-init integration (the resulting template has cloud-init enabled)
- Configurable storage pools, network settings, and ISO sources

Per-cluster settings (Proxmox API endpoint, node name, template VM ID, network
configuration, storage pools) are kept in separate `.pkrvars.hcl` files, so
the same Packer definitions can be reused across different Proxmox clusters.

Example — building a Debian 13 template:

```bash
packer build \
  -var-file secrets.pkrvars.hcl \
  -var-file mycluster.pkrvars.hcl \
  debian_13_trixie.pkr.hcl
```

Where `mycluster.pkrvars.hcl` contains cluster-specific values:

```hcl
proxmox_host     = "pve1.example.com:8006"
proxmox_node     = "pve1"
proxmox_api_user = "root@pam!for-packer"

vm_id   = "9001"
vm_name = "debian-13.3.0-amd64"

iso_url      = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.3.0-amd64-netinst.iso"
iso_checksum = "sha256:..."

iso_storage_pool        = "local"
cloud_init_storage_pool = "local-zfs"
disk_storage_pool       = "local-zfs"

http_interface = "eno1"

net_bridge      = "vmbr0"
net_ip_addr     = "10.0.0.250"
net_netmask     = "255.255.255.0"
net_gateway     = "10.0.0.1"
net_nameservers = "10.0.0.1"
```

The resulting template ID can then be referenced in this module's
`clone_vm_ids` map or `clone_vm_id` parameter.

## Usage

### Basic — single cluster with `for_each`

The simplest pattern: define cluster-wide defaults once, then describe each VM
with only its unique parameters.

```hcl
locals {
  cluster_defaults = {
    cluster_name = "pve1"
    node_name    = "pve1"
    vm_os        = "debian13"
    clone_vm_ids = {
      "debian12" = 9000
      "debian13" = 9001
    }
    initialization_datastore_id      = "local-zfs"
    initialization_dns_domain        = "example.com"
    initialization_dns_servers       = ["10.0.0.1"]
    initialization_ipv4_gateway      = "10.0.0.1"
    initialization_user_data_file_id = proxmox_virtual_environment_file.cloud_init[0].id
    enable_netbox                    = true
  }

  vms = {
    webserver = {
      vm_name      = "web1.example.com"
      vm_id        = 100
      cpu_cores    = 2
      memory_size  = 4096
      ipv4_address = "10.0.0.10/24"
      disk_size    = 20
    }
    database = {
      vm_name      = "db1.example.com"
      vm_id        = 101
      cpu_cores    = 4
      memory_size  = 8192
      ipv4_address = "10.0.0.11/24"
      disk_size    = 100
    }
  }
}

module "vm" {
  for_each  = local.vms
  source    = "./modules/proxmox-vm"
  providers = { proxmox = proxmox.pve1 }

  defaults    = local.cluster_defaults
  vm_name     = each.value.vm_name
  vm_id       = each.value.vm_id
  cpu_cores   = each.value.cpu_cores
  memory_size = each.value.memory_size

  network_interfaces = [{
    bridge       = "vmbr0"
    ipv4_address = each.value.ipv4_address
  }]

  disks = [{ size = each.value.disk_size }]
}
```

Key points:
- `defaults` carries all cluster-level settings in a single assignment
- `clone_vm_ids` maps OS identifiers to template IDs — the module automatically
  picks the right template based on `vm_os`
- `model` and `firewall` in `network_interfaces` default to `"virtio"` and
  `false` respectively, so you only need `bridge` and `ipv4_address`
- `disks.datastore_id` falls back to `initialization_datastore_id` when omitted

### Advanced — multiple clusters with `count`

When you need index arithmetic for node placement and IP calculation, use
`count` with `defaults`:

```hcl
locals {
  dc1_defaults = {
    cluster_name = "dc1"
    vm_os        = "debian12"
    clone_vm_ids = {
      "debian12" = data.proxmox_virtual_environment_vms.dc1_templates["dc1-node01"]
      "debian13" = data.proxmox_virtual_environment_vms.dc1_templates_13["dc1-node01"]
    }
    clone_node_name                  = "dc1-node01"
    initialization_datastore_id      = "ceph-hdd"
    initialization_dns_domain        = "internal.example.com"
    initialization_dns_servers       = ["10.1.0.53", "10.1.0.54"]
    initialization_user_data_file_id = proxmox_virtual_environment_file.dc1_cloud_init[0].id
  }
}

module "appserver" {
  source    = "./modules/proxmox-vm"
  count     = 3
  providers = { proxmox = proxmox.dc1 }

  defaults    = local.dc1_defaults
  vm_name     = "app${count.index + 1}.internal.example.com"
  node_name   = format("dc1-node%02d", count.index % 3 + 1)
  vm_id       = 2000 + count.index
  cpu_cores   = 4
  memory_size = 16384

  network_interfaces = [{
    bridge       = "vmbr0"
    vlan_id      = 100
    ipv4_address = "10.1.100.${10 + count.index}/24"
  }]

  disks = [{
    datastore_id = "ceph-ssd"
    size         = 50
  }]

  initialization_ipv4_gateway = "10.1.100.1"
}
```

Key points:
- `defaults` provides cluster-level values; per-module overrides (like
  `initialization_ipv4_gateway` or `disks.datastore_id`) take precedence
- `node_name` uses `format()` and modulo arithmetic for round-robin placement
- VMs that need a different OS just override `vm_os` — the correct template
  resolves automatically from `clone_vm_ids`

### Advanced — multiple network interfaces

VMs can have multiple interfaces on different VLANs:

```hcl
module "loadbalancer" {
  source    = "./modules/proxmox-vm"
  count     = 2
  providers = { proxmox = proxmox.dc1 }

  defaults    = local.dc1_defaults
  vm_name     = "lb${count.index + 1}.internal.example.com"
  node_name   = "dc1-node0${count.index + 1}"
  vm_id       = 3000 + count.index
  memory_size = 2048

  network_interfaces = [
    {
      bridge       = "vmbr100"
      ipv4_address = "10.1.100.${20 + count.index}/24"
    },
    {
      bridge       = "vmbr200"
      ipv4_address = "10.1.200.${20 + count.index}/24"
    },
    {
      bridge       = "vmbr0"
      ipv4_address = "203.0.113.${10 + count.index}/29"
      ipv6_address = "2001:db8::${10 + count.index}/64"
    }
  ]

  disks = [{ size = 10 }]

  initialization_ipv4_gateway = "10.1.100.1"
}
```

### Mixed — `for_each` and `count` in the same project

You can freely mix both patterns. Use `for_each` for unique single-instance
VMs and `count` for groups that need index arithmetic:

```hcl
# Single-instance VMs via for_each
module "infra_vm" {
  for_each  = local.infra_vms
  source    = "./modules/proxmox-vm"
  providers = { proxmox = proxmox.dc1 }

  defaults    = local.dc1_defaults
  vm_name     = each.value.vm_name
  node_name   = each.value.node_name
  vm_id       = each.value.vm_id
  cpu_cores   = each.value.cpu_cores
  memory_size = each.value.memory_size

  network_interfaces = [{
    bridge       = "vmbr0"
    vlan_id      = each.value.vlan_id
    ipv4_address = each.value.ipv4_address
  }]

  disks = [{
    size         = each.value.disk_size
    datastore_id = each.value.disk_datastore
  }]

  initialization_ipv4_gateway = each.value.gateway
}

# Scaled-out workers via count
module "worker" {
  source    = "./modules/proxmox-vm"
  count     = 5
  providers = { proxmox = proxmox.dc1 }

  defaults    = local.dc1_defaults
  vm_name     = "worker${count.index + 1}.internal.example.com"
  node_name   = format("dc1-node%02d", count.index % 3 + 1)
  vm_id       = 4000 + count.index
  cpu_cores   = 8
  memory_size = 32768

  network_interfaces = [{
    bridge       = "vmbr0"
    vlan_id      = 200
    ipv4_address = "10.1.200.${100 + count.index}/24"
  }]

  disks = [{ size = 64 }]

  initialization_ipv4_gateway = "10.1.200.1"
}
```

## The `defaults` parameter

The `defaults` object carries cluster-level or project-level settings. Every
field in `defaults` has a corresponding module variable. Resolution order:

1. **Explicit parameter** — always wins when non-null
2. **`defaults.clone_vm_ids[vm_os]`** — automatic template lookup (for `clone_vm_id` only)
3. **`defaults.<field>`** — fallback from the defaults object

Special behaviors:
- `clone_vm_id`: if not set explicitly, looked up from `defaults.clone_vm_ids`
  using the effective `vm_os` as key. This means changing just `vm_os` on a VM
  automatically selects the matching template.
- `clone_node_name`: falls back to the effective `node_name` if neither the
  explicit parameter nor `defaults.clone_node_name` is set.
- `enable_netbox`: ultimate fallback is `true` if not set anywhere.
- `disks.datastore_id`: falls back to the effective `initialization_datastore_id`
  when omitted from a disk entry.

### `defaults` fields

| Field | Type | Description |
|-------|------|-------------|
| `cluster_name` | `string` | Proxmox cluster name (for Netbox registration) |
| `node_name` | `string` | Default Proxmox node for VM placement |
| `vm_os` | `string` | Default OS identifier (e.g. `debian13`) |
| `clone_vm_id` | `number` | Default template VM ID |
| `clone_vm_ids` | `map(number)` | Map of `vm_os` → template VM ID for auto-lookup |
| `clone_node_name` | `string` | Node where templates reside |
| `initialization_datastore_id` | `string` | Datastore for cloud-init and disk fallback |
| `initialization_dns_domain` | `string` | DNS domain for cloud-init |
| `initialization_dns_servers` | `list(string)` | DNS servers for cloud-init |
| `initialization_ipv4_gateway` | `string` | Default IPv4 gateway |
| `initialization_user_data_file_id` | `string` | Cloud-init user data file ID |
| `enable_netbox` | `bool` | Whether to create Netbox resources |

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `defaults` | `object(...)` | `{}` | no | Default values (see above) |
| `vm_name` | `string` | — | **yes** | VM name (FQDN) |
| `vm_id` | `number` | — | **yes** | Proxmox VM ID |
| `network_interfaces` | `list(object)` | — | **yes** | Network interfaces (see below) |
| `disks` | `list(object)` | — | **yes** | Disk definitions (see below) |
| `cluster_name` | `string` | `null` | no | Proxmox cluster name |
| `node_name` | `string` | `null` | no | Proxmox node name |
| `vm_os` | `string` | `null` | no | OS identifier for tagging and template lookup |
| `clone_vm_id` | `number` | `null` | no | Template VM ID to clone |
| `clone_node_name` | `string` | `null` | no | Node where template resides |
| `memory_size` | `number` | `1024` | no | RAM in MB |
| `cpu_cores` | `number` | `1` | no | Number of CPU cores |
| `cpu_type` | `string` | `"host"` | no | CPU type |
| `initialization_datastore_id` | `string` | `null` | no | Datastore for cloud-init drive |
| `initialization_dns_domain` | `string` | `null` | no | DNS domain |
| `initialization_dns_servers` | `list(string)` | `null` | no | DNS servers |
| `initialization_ipv4_gateway` | `string` | `null` | no | IPv4 gateway |
| `initialization_user_data_file_id` | `string` | `null` | no | Cloud-init user data file ID |
| `enable_netbox` | `bool` | `null` | no | Create Netbox resources (fallback: `true`) |
| `provisioner_extra_commands` | `list(string)` | `[]` | no | Additional shell commands run via remote-exec after creation |

### `network_interfaces` object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `bridge` | `string` | — | Bridge name (e.g. `vmbr0`) |
| `model` | `string` | `"virtio"` | NIC model |
| `firewall` | `bool` | `false` | Enable Proxmox firewall |
| `vlan_id` | `number` | `null` | VLAN tag |
| `ipv4_address` | `string` | `null` | IPv4 address with CIDR (e.g. `10.0.0.1/24`) |
| `ipv6_address` | `string` | `null` | IPv6 address with prefix |

### `disks` object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `size` | `number` | — | Disk size in GB |
| `datastore_id` | `string` | `null` | Datastore (falls back to `initialization_datastore_id`) |
| `interface` | `string` | `null` | Disk interface (auto-assigned as `scsi0`, `scsi1`, ...) |
| `file_format` | `string` | `"raw"` | Disk format |
| `iothread` | `bool` | `true` | Enable IO thread |

## Outputs

| Name | Description |
|------|-------------|
| `vm` | The `proxmox_virtual_environment_vm` resource |
| `netbox_vm` | The `netbox_virtual_machine` resource (or `null` if Netbox disabled) |
| `ifaces` | Map of network interfaces with runtime data (MAC, IPs) |
| `disks` | Map of disks with runtime data |

## Notes

### State migration when switching to `for_each`

When converting individual module blocks to a single `for_each` block, existing
state must be moved to prevent recreation:

```bash
tofu state mv 'module.myvm' 'module.cluster_vm["myvm"]'
```

Always run `tofu plan` after migration to verify zero changes.

### Lifecycle

The module ignores changes to `initialization[0].user_data_file_id` and
`clone[0].node_name` to prevent unnecessary updates after initial provisioning.
