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
| Storage          | [Rook-Ceph](https://rook.io/) (planned; 0 usable OSDs on current hardware) + [local-path-provisioner](https://github.com/rancher/local-path-provisioner) (interim, node-local, cluster default `StorageClass` for now) |
| Ingress          | [Envoy Gateway](https://gateway.envoyproxy.io/) (Gateway API) — `internal` Gateway (VPN/tailnet only) + `external` Gateway (public, behind cloudflared) |
| Observability    | [Gatus](https://github.com/TwiN/gatus) (status page) + metrics-server (`kubectl top`/k9s) |
| LAN DNS          | [AdGuard Home](https://adguard.com/adguard-home/) — resolves `*.internal.alexandremathieu.com` (the ISP router can't do local DNS records) |
| Dependency mgmt  | [Renovate](https://docs.renovatebot.com/)                   |
| Tool versions    | [asdf](https://asdf-vm.com/)                                 |
| VPN host provisioning | [OpenTofu](https://opentofu.org/) (Oracle Cloud VM + DNS only, see below) |

See [PROJECT_BRIEF.md](../PROJECT_BRIEF.md), [E2E_PLAN.md](../E2E_PLAN.md), and
[HARDWARE_PLAN.md](../HARDWARE_PLAN.md) for the full rationale and rollout plan.

## Repo layout

```
home-ops/
├── .tool-versions              # asdf-managed CLI versions
├── talos/                      # talhelper config + generated machine configs (gitignored,
│                                 # except talsecret.sops.yaml -- SOPS/age-encrypted, see
│                                 # .sops.yaml -- committed on purpose)
├── terraform/
│   └── headscale/               # OpenTofu: Oracle Cloud VM + DNS for Headscale -- the one
│                                 # place in the repo Terraform is used (real cloud
│                                 # resources with real lifecycle; see secret-zero.md for
│                                 # why it's not used for secrets)
├── bootstrap/
│   ├── kustomize/               # secret-zero: op inject + kubectl apply, no Terraform
│   └── helmfile/                # installs Cilium before Flux exists (chicken-and-egg:
│                                 # nothing gets pod networking without it, Flux included)
├── kubernetes/
│   ├── flux/cluster/           # Flux's own bootstrap manifests + the one top-level sync
│   └── apps/                   # one tree grouped by K8s namespace (onedr0p/buroa convention):
│                                # kube-system (cilium, metrics-server, local-path-provisioner),
│                                # cert-manager, external-secrets,
│                                # rook-ceph, networking (envoy-gateway, cloudflared,
│                                # headscale-subnet-router, gateway-api-crds), observability
│                                # (gatus), default (home apps)
│                                # -- each component as <name>/{ks.yaml, app/, config/}
├── .github/workflows/          # Renovate, CI (kubeconform validation)
└── docs/runbooks/              # the handful of manual, non-GitOps steps
```

## Hardware

Running single-node for now on a **HP ProDesk 600 G4 Mini** (i5-8500T, 8GB RAM, 256GB
SSD). `talos/talconfig.yaml`'s `nodes:` block has just this one real node; see
[`docs/runbooks/cluster-bootstrap.md`](docs/runbooks/cluster-bootstrap.md) for the
bare-metal install steps and known single-node limitations (no etcd HA, no spare disk
for Rook-Ceph OSDs yet, 8GB RAM is tight). More nodes get appended to the same file when
they arrive — nothing else in the repo changes.

## Local dev cluster

Also still useful even with real hardware up — a disposable place to test a
Renovate-proposed chart bump or a new app before it touches the real node. Runs as a
real Talos + Kubernetes cluster locally:

```bash
talosctl cluster create docker --name home-ops-dev --workers 0 --memory-controlplanes 6GB \
  --config-patch '{"cluster":{"network":{"cni":{"name":"none"}},"proxy":{"disabled":true}}}'
```

This is genuine Talos/Kubernetes, not a stand-in like kind/k3s. It's single-control-plane
(not the 3-CP topology `talos/talconfig.yaml` describes for real hardware) — the QEMU
provisioner that would give 3-CP locally hits a known kexec hang on macOS/Apple Silicon
([siderolabs/talos#13108](https://github.com/siderolabs/talos/issues/13108)); Docker
sidesteps it entirely (no VM boot/kexec involved) at the cost of not exercising etcd HA
locally. `--memory-controlplanes` matters: the default 2GB is too tight once Flux and a
few HelmReleases are running and causes controller crash loops. The `--config-patch`
disables Talos's default Flannel/kube-proxy the same way `talos/talconfig.yaml` does for
real hardware — full docs/runbooks/cluster-bootstrap.md#why-docker-not-qemu has the
details, and see "Manual steps" below for why Cilium then needs a separate install step
before Flux. Swapping `talos/talconfig.yaml` node definitions for real IPs is the only
repo change needed once hardware exists. What can't be validated locally: etcd quorum
across multiple nodes, Cilium L2 announcements on a real LAN, Rook-Ceph (no raw block
devices in a Docker-provisioned node), Headscale subnet router reachability from outside,
and end-to-end cloudflared tunnel routing.

## Manual steps (everything else is `git push`)

1. [`docs/runbooks/cluster-bootstrap.md`](docs/runbooks/cluster-bootstrap.md) — bring up
   the node(s) (first apply to a node in maintenance mode needs
   `talhelper gencommand apply --extra-flags "--insecure"`, or you'll hit
   `x509: certificate signed by unknown authority` — see the runbook), then
   `helmfile -f bootstrap/helmfile/helmfile.yaml sync` to install Cilium *before* Flux
   (nothing, including Flux's own controllers, gets pod networking without it — Talos's
   CNI is disabled), then `flux bootstrap github`
2. [`docs/runbooks/secret-zero.md`](docs/runbooks/secret-zero.md) — `op inject | kubectl apply`
   from an authenticated local `op` session
3. [`docs/runbooks/cloudflare-setup.md`](docs/runbooks/cloudflare-setup.md) — API token +
   Tunnel token into 1Password (not required for Headscale/VPN, only for public exposure
   and the internal Gateway's TLS cert)
4. [`docs/runbooks/headscale-oracle-cloud.md`](docs/runbooks/headscale-oracle-cloud.md) —
   `tofu apply` the Oracle Cloud Always Free VM (outside the cluster by design, provisioned
   via [`terraform/headscale/`](terraform/headscale)), then wire the in-cluster subnet
   router to it
5. AdGuard Home (`kubernetes/apps/networking/adguard-home`) — once it's `Ready`, check its
   assigned LoadBalancer IP (`kubectl get svc -n networking -l app.kubernetes.io/name=adguard-home`)
   and set it as the **primary** DHCP DNS server on the router (Nokia-provided, ebox) —
   secondary should stay a public resolver (e.g. `1.1.1.1`) so general internet DNS keeps
   working via fallback if this pod is ever down. Also swap the placeholder IP in
   `kubernetes/apps/networking/adguard-home/app/helmrelease.yaml`'s DNS rewrite for the
   internal Gateway's actual assigned address once known.

## Status

Bootstrapping. Local dev cluster live with Flux reconciling; 1Password and Cloudflare are
both set up and verified end-to-end (`cert-manager-config`, `cloudflared` both `Ready`).
Headscale hosting location decided (Oracle Cloud Always Free VM, runbook above) but not
yet provisioned. First real node (HP ProDesk 600 G4 Mini, single-node for now) purchased
and `talos/talconfig.yaml` updated for it — not yet installed/bootstrapped, see
`docs/runbooks/cluster-bootstrap.md`. Remaining: install Talos on the real node, stand up
Headscale, and the apps themselves. See task list / commit history for current phase.
