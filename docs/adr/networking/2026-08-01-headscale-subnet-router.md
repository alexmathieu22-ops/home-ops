# Run a plain Tailscale client as a Headscale subnet router

Date: 2026-08-01

## Status

Accepted

## Context

The home LAN needs to be reachable over the tailnet, and this cluster runs self-hosted
Headscale rather than Tailscale's own coordination server. The Tailscale Kubernetes
Operator is incompatible with self-hosted Headscale (only implements Tailscale's v1 API;
see juanfont/headscale#3081, #3086), so it isn't an option here.

## Decision

`kubernetes/apps/vpn/headscale-subnet-router`: plain Tailscale client advertising the
home LAN CIDR into the tailnet. `TS_KUBE_SECRET=""` disables containerboot's default of
writing state to a Secret (which takes precedence over `TS_STATE_DIR` on Kubernetes),
keeping state only on the pod's own PVC and avoiding extra RBAC. `TS_LOGIN_SERVER` is not
a real containerboot env var (confirmed against current `cmd/containerboot` source — it's
silently ignored, which is why this was connecting to Tailscale's own coordination server
instead of Headscale); `--login-server` has to go through `TS_EXTRA_ARGS` instead. No
`--advertise-tags`: Headscale rejects any tag not pre-declared as owned in an ACL policy,
and none is configured yet. The `vpn` namespace is split out from `networking`
specifically to scope its permissive PodSecurity labels (this workload needs
`NET_ADMIN`/`NET_RAW` and a hostPath `/dev/net/tun` mount) to only the workload that
needs them.

## Consequences

No tags can be advertised until an ACL policy declares and owns them. The `vpn`
namespace's relaxed PodSecurity labels apply only to this workload, not to `networking`
at large.
