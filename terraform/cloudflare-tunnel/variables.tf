variable "cloudflare_api_token" {
  description = "Cloudflare API token. Needs Zero Trust Tunnel edit + DNS edit on the zone -- a broader scope than the DNS-only token reused elsewhere in this repo (docs/runbooks/cloudflare-setup.md), so this one is separate."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID -- dashboard right sidebar on any zone overview page, or `Home` page URL"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Zone ID for `domain`, from the Cloudflare dashboard's zone overview page"
  type        = string
}

variable "tunnel_id" {
  description = "ID of the already-running `home-ops` tunnel (created via `cloudflared tunnel create`, not by this module -- see docs/runbooks/cloudflare-setup.md). Find it with `cloudflared tunnel list`, or from a running pod's logs (`kubectl logs -n networking -l app.kubernetes.io/name=cloudflared | grep tunnelID`)."
  type        = string
}

variable "domain" {
  description = "Base domain (must be the Cloudflare zone already used elsewhere in this repo)"
  type        = string
  default     = "alexandremathieu.com"
}

variable "external_gateway_service" {
  description = "In-cluster DNS name of the external Envoy Gateway's Service -- not stable across Gateway recreation, since Envoy Gateway derives it from the Gateway's UID. Re-check with: kubectl get svc -n networking -l gateway.envoyproxy.io/owning-gateway-name=external"
  type        = string
}
