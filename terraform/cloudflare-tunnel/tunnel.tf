# Manages the tunnel's ingress config and public DNS record only -- not the tunnel
# resource itself. The tunnel was created via `cloudflared tunnel create` and its
# token already lives in 1Password (docs/runbooks/cloudflare-setup.md); recreating it
# here would mean a new token and re-wiring the cluster for no benefit. Applying this
# takes over ingress management from the Zero Trust dashboard -- manual edits there
# will be reverted on the next `tofu apply`.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "home_ops" {
  account_id = var.cloudflare_account_id
  tunnel_id  = var.tunnel_id

  config {
    ingress_rule {
      hostname = "*.${var.domain}"
      service  = "http://${var.external_gateway_service}"
    }

    # Required catch-all: the last rule must match everything (no hostname/path).
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# ONE wildcard CNAME covers every current and future *.${var.domain} app -- matches
# the "one dashboard entry, then just commit an HTTPRoute" convention documented in
# docs/runbooks/cloudflare-setup.md.
resource "cloudflare_record" "tunnel_wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*"
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # must be 1 (automatic) when proxied
}
