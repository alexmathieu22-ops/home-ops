# 0013. Split Gateway API into internal and external Gateways

## Status

Accepted

## Context

Traffic reaching this cluster falls into two distinct trust/routing zones: internal-only
traffic over the Headscale VPN, and public traffic terminated at Cloudflare's edge and
tunneled in by cloudflared. Each needs different TLS handling and Service exposure.

The Gateway API CRDs are not a separate component here (Cilium only does
CNI/LB-IPAM/L2, it doesn't install them) — `envoy-gateway`'s `gateway-helm` chart bundles
both Envoy Gateway's own CRDs and the Gateway API experimental-channel CRDs via a `crds`
subchart dependency (`values.crds.enabled: true`, the chart default; see
[gateway-helm/charts/crds](https://github.com/envoyproxy/gateway/tree/main/charts/gateway-crds-helm)),
installed through Helm's native `crds/` directory convention. That convention only
installs CRDs on first `helm install` and never touches them again on `helm upgrade` —
the root `apps` Kustomization (`kubernetes/flux/cluster/sync.yaml`) works around this with
a nested patch (patches every child Kustomization, which in turn patches every
HelmRelease it creates) setting `install.crds`/`upgrade.crds: CreateReplace`, so CRD
schemas actually keep up with chart upgrades cluster-wide (same pattern as
onedr0p/home-ops). This also fixes a documented Helm limitation with large CRDs living in
`templates/` rather than the native dir (helm/helm#12277).

## Decision

`kubernetes/apps/networking/envoy-gateway/config/` — matches onedr0p/home-ops's pattern.
`internal` (`*.internal.alexandremathieu.com`, HTTP + HTTPS via a cert-manager
`letsencrypt-dns01` cert) gets a Cilium LB-IPAM LoadBalancer IP, reachable over the
Headscale subnet router/VPN. `external` (`*.alexandremathieu.com`, HTTP-only —
Cloudflare terminates TLS at its own edge, and the tunnel connection is already
encrypted, so no cert-manager cert is needed) is forced to `ClusterIP` via a custom
`EnvoyProxy` resource referenced through `Gateway.spec.infrastructure.parametersRef` — it
only ever needs to be reached in-cluster, by cloudflared, so a LoadBalancer would
needlessly burn one of the few IPs in Cilium's LB-IPAM pool and expose it on the LAN for
no reason. cloudflared gets ONE static public-hostname entry
(`*.alexandremathieu.com` → the external Gateway's Service) instead of one dashboard
entry per app; every future public app is then just an `HTTPRoute` addition (see
`docs/runbooks/cloudflare-setup.md`).

That static public-hostname entry and its wildcard DNS record are managed by
`terraform/cloudflare-tunnel`, not clicked in by hand — it references the tunnel (created
via `cloudflared tunnel create`) by ID rather than owning the tunnel resource itself,
since recreating that resource in Terraform would mint a new token and force re-wiring
the 1Password item + a cloudflared rollout for no benefit. Same rationale as
`terraform/headscale` being its own root module rather than folded into one big
`terraform/` state: independent lifecycles, independent blast radius.

## Consequences

Every future publicly-reachable app only needs an `HTTPRoute` — no per-app cloudflared
dashboard entry, no per-app LoadBalancer IP. Internal-only apps route through the
`internal` Gateway and consume one of Cilium's LB-IPAM pool IPs each. See also
[0001](../flux/0001-split-ks-yaml-for-crd-cr-races.md) for the `ks.yaml` split this component
follows, and [0016](0016-flux-github-webhook-receiver.md) for another consumer of the
same `external` Gateway + cloudflared tunnel path.
