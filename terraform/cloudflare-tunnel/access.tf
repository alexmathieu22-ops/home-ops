# Gates the public Gatus status page at Cloudflare's edge -- traffic never reaches the
# tunnel/cluster without an allowed email completing a one-time-PIN login first. No
# passwords, no external IdP, no changes needed in Gatus itself. destinations (not the
# deprecated domain/self_hosted_domains) covers both public hostnames that resolve to
# the same page (see gatus's HelmRelease route.app.hostnames).
# Cloudflare rejects direct API deletes of application-owned policies ("invalid
# endpoint for deleting application-owned policies") -- the policy above is what
# actually removes it, so just drop the old standalone resource from state.
removed {
  from = cloudflare_zero_trust_access_policy.gatus

  lifecycle {
    destroy = false
  }
}

resource "cloudflare_zero_trust_access_application" "gatus" {
  account_id       = var.cloudflare_account_id
  name             = "Gatus Status Page"
  type             = "self_hosted"
  session_duration = "24h"

  destinations = [
    {
      type = "public"
      uri  = "status.${var.domain}"
    },
    {
      type = "public"
      uri  = "gatus.${var.domain}"
    }
  ]

  policies = [
    {
      name       = "Allow owner"
      precedence = 1
      decision   = "allow"

      include = [
        for email in var.access_allowed_emails : {
          email = { email = email }
        }
      ]
    }
  ]
}
