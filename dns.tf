locals {
  dns_provider = var.dns_provider != null ? var.dns_provider : try(var.defaults.dns_provider, null)
  dns_hostname = split(".", var.vm_name)[0]
  dns_domain   = join(".", slice(split(".", var.vm_name), 1, length(split(".", var.vm_name))))
  dns_ip       = split("/", var.network_interfaces[0].ipv4_address)[0]
  dns_zone     = var.dns_zone != null ? var.dns_zone : try(var.defaults.dns_zone, "${local.dns_domain}.")
  dns_ttl      = var.dns_ttl != null ? var.dns_ttl : try(var.defaults.dns_ttl, 3600)
}

# --- OPNSense Unbound host override ---
resource "opnsense_unbound_host_override" "forward" {
  count       = local.dns_provider == "opnsense" ? 1 : 0
  enabled     = true
  description = "Managed by OpenTofu - ${var.vm_name}"
  hostname    = local.dns_hostname
  domain      = local.dns_domain
  server      = local.dns_ip
  depends_on  = [proxmox_virtual_environment_vm.vm]
}

# --- RFC2136 dynamic update (Bind, PowerDNS, Knot, etc.) ---
resource "dns_a_record_set" "forward" {
  count      = local.dns_provider == "rfc2136" ? 1 : 0
  zone       = local.dns_zone
  name       = local.dns_hostname
  addresses  = [local.dns_ip]
  ttl        = local.dns_ttl
  depends_on = [proxmox_virtual_environment_vm.vm]
}
