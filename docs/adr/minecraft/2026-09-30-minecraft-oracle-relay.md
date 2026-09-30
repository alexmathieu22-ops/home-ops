# Expose Minecraft publicly through a relay on the Headscale VM

Date: 2026-09-30

## Status

Accepted

## Context

A vanilla Minecraft Java server for me and a few friends, reachable publicly at a hostname
on my domain (friends aren't on the tailnet). Minecraft Java is raw TCP, not HTTP. Every
public app so far goes Cloudflare edge → cloudflared → the `external` Gateway (see
[gateway-api-internal-external-split](../networking/2026-08-16-gateway-api-internal-external-split.md)),
and that path can't carry it:

- Cloudflare's proxy (orange cloud) parses HTTP at its edge — a Minecraft handshake is
  rejected there regardless of port, before the tunnel, Envoy or any port mapping is
  involved. Proxying raw TCP is Spectrum, a paid add-on.
- A Tunnel can carry TCP, but only to clients running `cloudflared access tcp` (or WARP)
  themselves — the Minecraft client can't connect to a tunnel hostname directly.

Rejected alternatives:

- **Router port-forward + DDNS**: works (the Ebox connection has a real public IP, no
  CGNAT), but publishes the home WAN IP — everything else stays behind Cloudflare — and
  needs a DDNS updater since the residential IP is dynamic.
- **playit.gg**: free, no port-forward, hides the IP, but adds a third party in the path
  and a custom domain is paid.

## Decision

Relay through the Headscale VM on Oracle Cloud (see
[`docs/runbooks/headscale-oracle-cloud.md`](../../runbooks/headscale-oracle-cloud.md)),
which already has a static public IP, a Terraform-managed DNS record, and a Tailscale
client on the tailnet. A `socat` systemd unit on the VM listens on a public port and
forwards to the Minecraft `LoadBalancer` Service's LAN IP, reached over the tailnet
through the subnet router's advertised `192.168.18.0/24` route (the VM's client runs with
`--accept-routes`). The Service's IP is pinned (`lbipam.cilium.io/ips: 192.168.18.220`)
so the relay target never moves.

Public port is `41337`, not `25565` — not a security control, just far fewer drive-by
scanners; an SRV record (`_minecraft._tcp.mc`) lets players type only
`mc.alexandremathieu.com`. Access control is the server's own enforced whitelist plus
`online-mode` (Microsoft account auth, the image default). A `CiliumNetworkPolicy`
restricts the pod's egress to DNS and the public internet, so a server compromise can't
reach the LAN or other pods.

Pinned to home-ops-2 via `nodeSelector` — home-ops-1 (8GB) already runs the control plane,
Prometheus and Home Assistant; the 3G heap + JVM overhead fits the worker's 8GB.
`storageClass: local-path` for the same no-OSDs-yet reason as Home Assistant.

The VM's `user_data` is now in `ignore_changes`: cloud-init only runs on first boot, so
template edits never reached the running VM anyway, and letting them through risked
replacing the instance (new IP, Headscale DB lost). Template changes are applied to the
live VM by hand per the runbook.

## Consequences

- Minecraft (and the tailnet) now share one point of failure: the VM. Its 50 Mbps cap and
  1/8 OCPU are ample for a handful of players; relaying is near-zero CPU.
- The server sees every player as coming from the relay, so IP bans are meaningless —
  moderation is by account (whitelist/ban by name).
- The world lives on home-ops-2's disk with no backup until a backup sidecar
  (`itzg/mc-backup`) or Ceph arrives.
- `VERSION` is pinned — bump it deliberately (and for security fixes), since a world
  opened by a newer server can't be downgraded.
