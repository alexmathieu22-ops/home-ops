# home-ops

Personal homelab, fully as code: Talos Linux + Kubernetes, GitOps via Flux CD, secrets via
1Password + External Secrets Operator, public exposure via Cloudflare Tunnel, VPN via
self-hosted Headscale.

## Stack

| Layer            | Choice                                                    |
| ---------------- | ---------------------------------------------------------- |
| OS / Kubernetes  | [Talos Linux](https://www.talos.dev/)                      |
| GitOps           | [Flux CD](https://fluxcd.io/)                               |
| CNI              | [Cilium](https://cilium.io/) (LB-IPAM + L2 announcements, no MetalLB) |
| Public exposure  | [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) (cloudflared) |
| VPN              | Self-hosted [Headscale](https://headscale.net/) + Tailscale subnet router |
| Secrets          | [1Password Service Account](https://developer.1password.com/docs/service-accounts/) via [External Secrets Operator](https://external-secrets.io/) (`1password-sdk` provider) — zero SOPS |
| Storage          | [Rook-Ceph](https://rook.io/)                                |
| Ingress          | [Envoy Gateway](https://gateway.envoyproxy.io/) (Gateway API) |
| Observability    | kube-prometheus-stack + Loki                                |
| Dependency mgmt  | [Renovate](https://docs.renovatebot.com/)                   |
| Tool versions    | [asdf](https://asdf-vm.com/)                                 |

See [PROJECT_BRIEF.md](../PROJECT_BRIEF.md), [E2E_PLAN.md](../E2E_PLAN.md), and
[HARDWARE_PLAN.md](../HARDWARE_PLAN.md) for the full rationale and rollout plan.

## Repo layout

```
home-ops/
├── .tool-versions              # asdf-managed CLI versions
├── talos/                      # talhelper config + generated machine configs (gitignored)
├── terraform/bootstrap/        # OpenTofu: pushes 1Password secret-zero into the cluster
├── kubernetes/
│   ├── flux/cluster/           # Flux's own bootstrap manifests
│   ├── infrastructure/         # Cilium, cert-manager, cloudflared, external-secrets,
│   │                           # Longhorn, Envoy Gateway, headscale-subnet-router, monitoring
│   └── apps/                   # immich, home-assistant, jellyfin, paperless-ngx, homepage
├── .github/workflows/          # Renovate, CI (kubeconform validation)
└── docs/runbooks/              # the handful of manual, non-GitOps steps
```

## Local dev cluster

Hardware (3× Beelink EQ12 Pro) hasn't been purchased yet. Until it arrives, everything is
developed against a real Talos + Kubernetes cluster running locally via the Docker
provisioner:

```bash
talosctl cluster create --name home-ops-dev --controlplanes 3 --workers 0
```

This is genuine Talos/Kubernetes, not a stand-in like kind/k3s. Swapping `talos/talconfig.yaml`
node definitions for real IPs is the only change needed once hardware exists. What can't be
validated locally: Cilium L2 announcements on a real LAN, Headscale subnet router reachability
from outside, and end-to-end cloudflared tunnel routing.

## Manual steps (everything else is `git push`)

1. [`docs/runbooks/cluster-bootstrap.md`](docs/runbooks/cluster-bootstrap.md) — `talosctl bootstrap`
2. [`docs/runbooks/secret-zero.md`](docs/runbooks/secret-zero.md) — one `tofu apply` from an
   authenticated local `op` session

## Status

Bootstrapping. See task list / commit history for current phase.
