resource "cloudflare_record" "headscale" {
  zone_id = var.cloudflare_zone_id
  name    = var.headscale_subdomain
  type    = "A"
  content = oci_core_instance.headscale.public_ip
  proxied = false # must be DNS-only: Headscale clients need to reach the VM directly, and
  # Cloudflare's proxy doesn't forward the UDP DERP traffic anyway
  ttl = 300
}
