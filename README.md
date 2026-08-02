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
├── bootstrap/kustomize/        # secret-zero: op inject + kubectl apply, no Terraform
├── kubernetes/
│   ├── flux/cluster/           # Flux's own bootstrap manifests + the two top-level syncs
│   ├── infrastructure/         # Cilium, cert-manager, cloudflared, external-secrets,
│   │                           # Rook-Ceph, Envoy Gateway, headscale-subnet-router, monitoring
│   │                           # -- each as <name>/{ks.yaml, app/, config/}
│   └── apps/                   # immich, home-assistant, jellyfin, paperless-ngx, homepage
├── .github/workflows/          # Renovate, CI (kubeconform validation)
└── docs/runbooks/              # the handful of manual, non-GitOps steps
```

## Local dev cluster

Hardware (3× Beelink EQ12 Pro) hasn't been purchased yet. Until it arrives, everything is
developed against a real Talos + Kubernetes cluster running locally:

```bash
talosctl cluster create docker --name home-ops-dev --workers 0
```

This is genuine Talos/Kubernetes, not a stand-in like kind/k3s. It's single-control-plane
(not the 3-CP topology `talos/talconfig.yaml` describes for real hardware) — the QEMU
provisioner that would give 3-CP locally hits a known kexec hang on macOS/Apple Silicon
([siderolabs/talos#13108](https://github.com/siderolabs/talos/issues/13108)); Docker
sidesteps it entirely (no VM boot/kexec involved) at the cost of not exercising etcd HA
locally. Swapping `talos/talconfig.yaml` node definitions for real IPs is the only change
needed once hardware exists. What can't be validated locally: etcd quorum across multiple
nodes, Cilium L2 announcements on a real LAN, Rook-Ceph (no raw block devices in a
Docker-provisioned node), Headscale subnet router reachability from outside, and
end-to-end cloudflared tunnel routing.

## Manual steps (everything else is `git push`)

1. [`docs/runbooks/cluster-bootstrap.md`](docs/runbooks/cluster-bootstrap.md) — `talosctl bootstrap`
2. [`docs/runbooks/secret-zero.md`](docs/runbooks/secret-zero.md) — `op inject | kubectl apply`
   from an authenticated local `op` session

## Status

Bootstrapping. See task list / commit history for current phase.
