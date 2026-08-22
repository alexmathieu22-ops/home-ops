# 0009. Expose Home Assistant via a plain LoadBalancer Service

## Status

Accepted

## Context

Adapted from onedr0p/home-ops and buroa/k8s-gitops, not copied: this cluster has no
Multus CNI or VLAN segmentation, so `k8s.v1.cni.cncf.io/networks` (a dedicated IoT VLAN
IP, used by both references) isn't an option. There is also no working network-wide
internal DNS yet — AdGuard was pulled pending the UniFi gateway project (see
[0014](0014-adguard-home-internal-dns-deferred.md)) — and a smart-home panel is more
sensitive than a status page to leave path-dependent on that.

## Decision

No Gateway API route or Cloudflare Access, unlike either reference — exposed instead as a
`LoadBalancer` Service straight from Cilium's LB-IPAM, getting its own LAN IP directly
(`kubectl get svc -n default home-assistant-app`), no hostname/DNS/TLS needed.
`storageClass: local-path`, not `ceph-block`, for the same no-OSDs-yet reason as
`headscale-subnet-router` (see [0006](0006-rook-ceph-topology-and-local-path-interim.md))
— migrate once Ceph is actually live. No `ExternalSecret`/integration API keys (weather
providers, etc., in onedr0p's) — add if/when specific integrations need them.

## Consequences

Home Assistant is reachable only by its LB-IPAM IP directly, with no hostname or TLS,
until internal DNS exists again. Revisit the exposure method (Gateway route, hostname)
once internal DNS is back, and revisit `storageClass` once Ceph is actually live.
