resource "cloudflare_dns_record" "headscale" {
  zone_id = var.cloudflare_zone_id
  name    = var.headscale_subdomain
  type    = "A"
  content = oci_core_instance.headscale.public_ip
  proxied = false # must be DNS-only: Headscale clients need to reach the VM directly, and
  # Cloudflare's proxy doesn't forward the UDP DERP traffic anyway
  ttl = 300
}

# cloudflare_record was renamed to cloudflare_dns_record in the v5 provider.
moved {
  from = cloudflare_record.headscale
  to   = cloudflare_dns_record.headscale
}

# Minecraft relay -- see docs/adr/minecraft/2026-09-30-minecraft-oracle-relay.md. DNS-only
# like headscale's: Cloudflare's proxy only speaks HTTP, and this specific record takes
# precedence over the tunnel's proxied `*` wildcard.
resource "cloudflare_dns_record" "minecraft" {
  zone_id = var.cloudflare_zone_id
  name    = "mc"
  type    = "A"
  content = oci_core_instance.headscale.public_ip
  proxied = false
  ttl     = 300
}

# Lets players type just `mc.<domain>` -- the Java client resolves this SRV record to find
# the non-default port.
resource "cloudflare_dns_record" "minecraft_srv" {
  zone_id  = var.cloudflare_zone_id
  name     = "_minecraft._tcp.mc"
  type     = "SRV"
  priority = 0
  ttl      = 300
  data = {
    priority = 0
    weight   = 5
    port     = var.minecraft_public_port
    target   = "mc.${var.domain}"
  }
}
