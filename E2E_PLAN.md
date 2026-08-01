# Homelab E2E Plan — Talos Kubernetes, GitOps, 1Password/ESO, Headscale VPN

## 0. Architecture recap

```
Internet ── Cloudflare Tunnel (cloudflared) ── public apps only, no open ports
Internet ── Headscale (free tier VPS) ── Tailscale mesh ── everything else (private)

Talos Kubernetes cluster (3 nodes, bare metal)
├── Cilium              (CNI, kube-proxy replacement, Gateway API,
│                         LB-IPAM + L2 announcements — replaces MetalLB)
├── cert-manager        (Let's Encrypt certs via DNS-01, for internal/VPN-only TLS)
├── cloudflared          (public exposure — no port-forward, no public IP needed)
├── external-secrets    (1Password Service Account provider)
├── Longhorn            (in-cluster PVCs) + NAS (bulk media, NFS)
├── Envoy Gateway        (Gateway API implementation, internal/VPN-only ingress)
├── Headscale subnet router (advertises home LAN CIDR into the tailnet)
├── kube-prometheus-stack + Loki (observability)
├── Flux CD              (GitOps reconciler — the thing that owns everything above)
└── apps/ (Immich, Home Assistant, Jellyfin, Paperless-ngx, ...)
```

Note: no `external-dns` for public records either — cloudflared routes by hostname
configured directly in the tunnel, not via DNS records pointing at a LoadBalancer IP.
`external-dns` can still be used for _internal_ split-horizon DNS if you want
`*.internal.yourdomain.com` to auto-resolve inside the tailnet.

Secrets model: **zero SOPS**. "Secret zero" (1Password Service Account token) is pushed
into the cluster once via Terraform/OpenTofu from your authenticated local `op` session.
Every other secret in every app flows through ExternalSecret → 1Password.

---

## Phase 0 — Prerequisites (before touching hardware)

- [ ] Register a domain (or use one you own) — this is your public + internal DNS root.
- [ ] Cloudflare account, domain's nameservers pointed at Cloudflare (free tier is fine).
- [ ] 1Password account + a dedicated **vault** for infra secrets (separate from personal vault).
- [ ] 1Password **Service Account** created, scoped only to that infra vault.
- [ ] GitHub (or Gitea/Forgejo if self-hosting Git later) account/org for the homelab repo.
- [ ] A place to run Headscale that's reachable from the public internet, at $0/month:
  - **Oracle Cloud "Always Free" tier ARM VM** (recommended) — genuinely free forever, not a
    trial. Keeps your remote-access path independent of your home internet/power.
  - **Or self-host at home** if your ISP gives you a real public IPv4 (check: compare your
    router's WAN IP to what an external site reports — if they differ, you're behind CGNAT and
    this path is closed). Run it on a small always-on device, _not_ inside the K8s cluster
    itself (so a cluster outage doesn't also lock you out of fixing it), port-forward one port,
    and use free DDNS (Cloudflare's DDNS updater, since you're on Cloudflare DNS anyway).
- [ ] Local workstation tooling via **asdf** — see `.tool-versions` below, plus the `op` CLI
      (1Password) separately, since there's no asdf plugin for it.
- [ ] 1Password + Cloudflare account/domain — deferred for now, needed before Phase 5.

---

## Phase -1 — Local bootstrap on a single machine (optional but recommended)

You don't need to wait for hardware to start building this. `talosctl` has a built-in
**Docker provisioner** that spins up a real, multi-node Talos Kubernetes cluster as containers
on a single machine (your laptop, or later reused as one of the homelab boxes):

```bash
talosctl cluster create \
  --name home-ops-dev \
  --controlplanes 3 \
  --workers 0
```

This is genuinely the same Talos + the same Kubernetes — not a different distro like k3s/kind —
so everything from Phase 1 onward (repo structure, Flux bootstrap, Cilium, cert-manager, ESO,
even most of your app HelmReleases) can be developed and validated against it exactly as you
would against real hardware. When your mini PCs arrive, you swap `talconfig.yaml`'s node
definitions from Docker containers to real IPs — the rest of the repo doesn't change.

What **won't** fully validate locally: Cilium L2 announcements with actual routable LAN IPs,
Headscale subnet router reachability from outside, and end-to-end `cloudflared` tunnel
routing (you can still develop the manifests and test cert-manager against Let's Encrypt
staging from a Docker-provisioned cluster — just not the "someone outside your house can
actually reach it" part). Everything else — 80–90% of the stack — is fair game.

Alternative: `talosctl cluster create --provisioner qemu` uses real VMs instead of containers —
slower to spin up, but closer to bare-metal behavior (real disks, real boot process) if you want
higher fidelity while iterating. Docker is faster for day-to-day repo iteration; QEMU is closer
to "dress rehearsal" before buying hardware.

This also gives you a permanent local dev/staging cluster even after the real hardware is
running — a place to test a Renovate-proposed chart bump or a new app before it touches
production.

---

## Phase 1 — Repo bootstrap

Create the repo (public is fine and recommended — easier to ask for help, and Renovate/GitHub
Actions work better on public repos for free-tier minutes):

```bash
gh repo create alexmathieu22/home-ops --public --clone
cd home-ops
asdf install   # picks up .tool-versions once it's committed
```

Target repo layout (standard "home-ops" convention — mirrors onedr0p/cluster-template and
buroa/k8s-gitops):

```
home-ops/
├── .tool-versions              # asdf: talosctl, talhelper, flux2, opentofu, kubectl, helm
├── talos/
│   ├── talconfig.yaml          # talhelper config (node IPs, disks, network)
│   └── clusterconfig/          # generated machine configs (gitignored or committed encrypted)
├── terraform/
│   └── bootstrap/              # OpenTofu: pushes 1Password secret-zero into cluster,
│                                # optionally manages Headscale VPS + Cloudflare DNS zone
├── kubernetes/
│   ├── flux/
│   │   └── cluster/            # Flux's own bootstrap manifests
│   ├── infrastructure/
│   │   ├── cilium/
│   │   ├── cert-manager/
│   │   ├── cloudflared/
│   │   ├── external-dns/       # optional, internal split-horizon DNS only
│   │   ├── external-secrets/
│   │   ├── longhorn/
│   │   ├── envoy-gateway/
│   │   ├── headscale-subnet-router/   # NOT the Tailscale Operator — incompatible with Headscale
│   │   └── monitoring/         # kube-prometheus-stack, loki
│   └── apps/
│       ├── immich/
│       ├── home-assistant/
│       ├── jellyfin/
│       ├── paperless-ngx/
│       └── homepage/
├── .github/workflows/          # Renovate, CI validation (kubeconform, flux diff)
└── docs/
    └── runbooks/                # the handful of non-GitOps bootstrap steps, documented
```

---

## Phase 2 — Talos cluster bring-up

1. Flash Talos ISO to USB (or PXE-boot it — nicer long-term, more setup now) for each node.
2. Boot all 3 nodes, discover them on the LAN:
   ```bash
   nmap -Pn -n -p 50000 192.168.1.0/24 -vv | grep Discovered
   ```
3. Write `talos/talconfig.yaml` (talhelper) describing your 3 nodes: static IPs, disk to
   install to, control-plane vs worker role (all 3 as control-plane is fine at this scale —
   gives you HA etcd without dedicating a node purely to control-plane).
4. Generate + apply configs:
   ```bash
   talhelper genconfig
   talhelper gencommand apply | bash
   ```
5. Bootstrap etcd on one control-plane node — **this is the one genuinely manual, undocumented-
   in-Git step**, same as it is for literally every Talos cluster:
   ```bash
   talosctl bootstrap -n <first-node-ip>
   ```
6. Pull kubeconfig, confirm nodes are `Ready`:
   ```bash
   talosctl kubeconfig -n <first-node-ip>
   kubectl get nodes
   ```

Document steps 1–6 in `docs/runbooks/cluster-bootstrap.md` — this is your only non-GitOps
runbook for the whole cluster lifecycle (re-run only on full rebuild/disaster recovery).

---

## Phase 3 — Secret zero (Terraform, no SOPS)

`terraform/bootstrap/main.tf` — reads the 1Password Service Account token from your local
`op` session (env var `OP_SERVICE_ACCOUNT_TOKEN`, never committed) and creates the one
Kubernetes Secret that External Secrets needs to bootstrap itself:

```hcl
provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "external_secrets" {
  metadata { name = "external-secrets" }
}

resource "kubernetes_secret" "onepassword_token" {
  metadata {
    name      = "onepassword-service-account-token"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
  }
  data = {
    token = var.onepassword_service_account_token
  }
}
```

```bash
export TF_VAR_onepassword_service_account_token=$(op read "op://infra/eso-service-account/token")
tofu -chdir=terraform/bootstrap apply
```

Run this once per cluster lifetime (and again only if you rotate the token). Everything
downstream references this Secret — never re-create it by hand.

---

## Phase 4 — Flux bootstrap

```bash
flux bootstrap github \
  --owner=alexmathieu22 \
  --repository=home-ops \
  --branch=main \
  --path=kubernetes/flux/cluster \
  --personal
```

From this point, **every change to the cluster is a `git push`.** Flux watches
`kubernetes/infrastructure` and `kubernetes/apps`; each subfolder has a `kustomization.yaml`

- a Flux `Kustomization` (`ks.yaml`) that reconciles a `HelmRelease` or raw manifests.

---

## Phase 5 — Core infrastructure (in dependency order)

Add each as a `HelmRelease` under `kubernetes/infrastructure/<name>/`, commit, let Flux
reconcile. Rough dependency order matters (Flux Kustomizations support `dependsOn`):

1. **Cilium** — CNI + kube-proxy replacement + Gateway API CRDs, with LB-IPAM and L2
   announcements enabled (`l2announcements.enabled=true`, `externalIPs.enabled=true`) —
   this is your MetalLB replacement, one component instead of two. Give it a small
   `CiliumLoadBalancerIPPool` from your LAN range for internal-only Services (e.g. the
   internal Envoy Gateway listener, reachable via the Headscale subnet router).
2. **cert-manager** — `ClusterIssuer` for Let's Encrypt, DNS-01 solver against Cloudflare
   (API token stored in 1Password, pulled via ExternalSecret) — used for internal/VPN-only
   TLS, since cloudflared handles TLS termination for public traffic itself.
3. **external-secrets** — `ClusterSecretStore` pointing at the 1Password SDK provider,
   using the secret-zero token from Phase 3.
4. **cloudflared** — Deployment (or DaemonSet) in-cluster, routes by hostname straight to
   `ClusterIP` Services — no LoadBalancer IP, no port-forward, no public IP needed at all.
   Public hostnames are configured in the tunnel, not via DNS records pointing at your IP.
5. **Longhorn** — default StorageClass for app PVCs; configure S3 (Backblaze B2) backup
   target early, not after you have data.
6. **Envoy Gateway** — the Gateway API implementation for internal/VPN-only traffic; one
   `Gateway` resource, reachable via the Cilium LB-IPAM IP over the tailnet.

---

## Phase 6 — VPN (Headscale)

1. Deploy Headscale to the VPS — either as a plain systemd/Docker service outside K8s (simplest,
   since it's the _entry point_ to your cluster and shouldn't depend on the cluster being up),
   or as a HelmRelease if you'd rather run it in-cluster and NAT-punch to it. Most homelabbers
   run it on the standalone VPS for exactly the "front door shouldn't depend on the thing it
   fronts" reason.
2. Install the Tailscale client on your and your girlfriend's devices, pointed at your
   Headscale server (`tailscale up --login-server=https://headscale.yourdomain.com`).
3. Deploy a **subnet router** (a small Tailscale container/pod advertising your home LAN CIDR)
   so both tailnet devices can reach the whole home network, not just the cluster.
4. **Not the Tailscale Kubernetes Operator** — worth noting explicitly so you don't spend
   time investigating it later: the Operator requires Tailscale's SaaS control plane (its
   v2 API + OAuth), and Headscale only implements the older v1 API. Headscale's own
   maintainers track this as likely infeasible to ever support. The subnet router above is
   not a simplified alternative — it's the only option compatible with self-hosted Headscale.
5. (Optional hardening) Run your own DERP relay on the VPS to drop the last dependency on
   Tailscale's public relay infrastructure.

---

## Phase 7 — Observability

`kube-prometheus-stack` (Prometheus + Grafana + Alertmanager) + Loki (or Grafana Alloy) as
HelmReleases under `infrastructure/monitoring/`. Do this **before** Phase 8 — debugging app
rollouts without metrics/logs is the single biggest time-sink in homelabs.

---

## Phase 8 — Applications

Per app, the repeatable pattern:

```
kubernetes/apps/immich/
├── namespace.yaml
├── helmrelease.yaml       # or kustomize + raw manifests if no official chart
├── externalsecret.yaml    # pulls DB password / API keys from 1Password
├── httproute.yaml         # or just a tailnet-only Service if not public
└── kustomization.yaml
```

Suggested rollout order (matches your stated priorities): Headscale/VPN validation app →
Immich → Home Assistant → Paperless-ngx → Jellyfin → Homepage/Glance dashboard.

---

## Phase 9 — Ops hygiene (ongoing, set up once)

- **Renovate** — bot PRs for every Helm chart/image bump across `kubernetes/`. Merge = deploy.
- **CI validation** — `kubeconform`/`flux diff` on every PR before merge, so bad YAML never
  reaches `main`.
- **Backups** — Longhorn → Backblaze B2 on a schedule; separately, back up your Git repo itself
  (it _is_ your infrastructure) and your 1Password vault export.
- **Disaster recovery test** — once things are stable, actually wipe a node and rebuild it from
  Phase 2 onward to prove the "as code" claim is real, not aspirational.

---

## Quick checklist summary

| Phase | Output                 | Manual step?                                          |
| ----- | ---------------------- | ----------------------------------------------------- |
| 0     | Accounts, domain, VPS  | Yes (one-time, outside Git)                           |
| 1     | Repo skeleton          | No                                                    |
| 2     | Talos cluster Ready    | Yes — `talosctl bootstrap` only                       |
| 3     | Secret zero in cluster | Yes — one `tofu apply` from local `op` session        |
| 4     | Flux reconciling       | Yes — one `flux bootstrap` command                    |
| 5     | Core infra live        | No — Git only                                         |
| 6     | VPN live               | Partial — Headscale server itself is standalone infra |
| 7     | Observability live     | No — Git only                                         |
| 8     | Apps live              | No — Git only                                         |
| 9     | Automation + backups   | No — Git only                                         |
