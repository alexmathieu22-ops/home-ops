# home-ops — Project Brief for Claude Code

This is the authoritative spec for a homelab repo. All architecture decisions below were
made deliberately in a prior planning conversation — implement them as-is rather than
substituting defaults, unless something is genuinely broken/incompatible, in which case
flag it before deviating.

## Identity

- GitHub account: `alexmathieu22`
- Repo: `alexmathieu22-ops/home-ops`, public
- Location: `~/Repos/home-ops`

## Non-negotiable architecture decisions (with rationale, so they aren't "corrected")

| Decision                                                                             | NOT this                                     | Why                                                                                                                                                                                                                                        |
| ------------------------------------------------------------------------------------ | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Talos Linux + Kubernetes                                                             | k3s, kubeadm                                 | User is a platform engineer, explicitly wants Talos                                                                                                                                                                                        |
| Flux CD for GitOps                                                                   | Argo CD                                      | Chosen deliberately                                                                                                                                                                                                                        |
| asdf for tool versions                                                               | mise, nvm, manual installs                   | User specified asdf explicitly                                                                                                                                                                                                             |
| Cilium CNI with **LB-IPAM + L2 announcements**                                       | MetalLB                                      | onedr0p (reference homelabber) dropped MetalLB in favor of Cilium-native since 1.13/1.14; confirmed still valid. One less component.                                                                                                       |
| **cloudflared (Cloudflare Tunnel)** for public exposure                              | Port-forward + real public IP + external-dns | Apartment, possible CGNAT, zero subscription cost, zero open ports                                                                                                                                                                         |
| **Headscale** (self-hosted control server) for VPN                                   | Tailscale SaaS                               | User wants zero recurring subscriptions; host on Oracle Cloud "Always Free" tier ARM VM (genuinely free forever) or self-hosted at home if a real public IPv4 is confirmed available                                                       |
| Headscale **subnet router** for LAN access                                           | Tailscale Kubernetes Operator                | **Operator is incompatible with Headscale** — it requires Tailscale's v2 API/OAuth; Headscale only implements v1 (see juanfont/headscale#3081, #3086). This is not a preference, it's a hard incompatibility. Do not attempt the Operator. |
| **1Password Service Account + External Secrets Operator's `1password-sdk` provider** | 1Password Connect server, Vaultwarden        | Lighter weight, no extra server to run. User does not want Vaultwarden since 1Password already covers household password management.                                                                                                       |
| **Zero SOPS** for secrets, except none at all if avoidable                           | SOPS+age for general secrets                 | "Secret zero" (the 1Password Service Account token) is pushed into the cluster via a one-time `op inject \| kubectl apply` from an authenticated local `op` CLI session — not committed to Git, not SOPS-encrypted. (Amended from the original OpenTofu plan: same one-time/not-committed guarantee, no state file. See `docs/runbooks/secret-zero.md`.) One narrow, deliberate exception: `talos/talsecret.yaml` (Talos's own cluster PKI/secrets) is SOPS+age-encrypted and committed as `talsecret.sops.yaml` (see `.sops.yaml`), because it has to exist *before* the cluster — and therefore ESO — does, so the 1Password+ESO path can't cover it. Every other secret in this repo still goes through 1Password + ESO, unchanged.                                      |
| **Rook-Ceph** for in-cluster storage                                                 | Longhorn                                     | Amended from the original Longhorn decision: most widely used in comparable reference repos (onedr0p/home-ops, buroa/k8s-gitops). Needs a dedicated raw block device per node — flagged in `HARDWARE_PLAN.md` as unbudgeted.               |
| Renovate for dependency updates                                                      | Manual version bumps                         | "Fully as code" requirement — every update should be a mergeable PR                                                                                                                                                                        |

**Amendment, not a correction (interim, explicitly time-boxed):** with Rook-Ceph stuck at
zero usable OSDs on the current single-disk hardware, `local-path-provisioner`
(node-local hostPath storage, no HA/replication) is running as the cluster's default
`StorageClass` so PVC-dependent apps aren't blocked entirely -- see
`kubernetes/apps/kube-system/local-path-provisioner` and
`docs/runbooks/cluster-bootstrap.md`'s "Known limitations running single-node" section.
This does not replace the Rook-Ceph decision above; it's a stopgap until a second disk
exists, at which point PVCs move back to `ceph-block` and this section should be removed.

## Hardware context (informs manifests but doesn't block software work)

- Current: a single HP ProDesk 600 G4 Mini (i5-8500T, 6C/6T, 8GB RAM, 256GB SSD), running
  standalone. `talos/talconfig.yaml`'s `nodes:` block reflects this one real node — see
  `docs/runbooks/cluster-bootstrap.md` for the bare-metal bring-up steps and
  `HARDWARE_PLAN.md` for the RAM/storage caveats this creates (no spare disk for
  Rook-Ceph OSDs yet, 8GB RAM on the low side). Additional nodes aren't required to match
  this box, but see `HARDWARE_PLAN.md`'s "3 identical nodes" rationale if buying more.
- Also useful as disposable dev/staging even with real hardware up:
  **develop against a local Talos cluster** via
  `talosctl cluster create docker --name home-ops-dev --workers 0` (single control-plane;
  the QEMU provisioner that would give the real 3-CP topology hits a kexec hang on
  macOS/Apple Silicon — see `docs/runbooks/cluster-bootstrap.md`). This is real Talos +
  real Kubernetes, not a stand-in like kind/k3s — the repo should work unmodified against
  this, swapping only `talconfig.yaml` node definitions once real hardware/IPs exist.
- What can't be validated locally: etcd HA across multiple nodes, Rook-Ceph (no raw block
  devices in a Docker-provisioned node), Cilium L2 announcements needing a real LAN,
  Headscale subnet router reachability from outside, end-to-end cloudflared tunnel
  routing. Build
  and unit-test the manifests for these anyway; full validation waits for hardware.

## Deferred by user (do not block on these — stub/document instead)

- 1Password account + vault + Service Account creation — not done yet
- Cloudflare account + domain — not done yet
- Where Headscale will run (Oracle Free Tier vs. home) — pending an ISP CGNAT check

Where these are required (e.g. `terraform/bootstrap`, cert-manager's Cloudflare API token,
the Headscale server itself), scaffold the code/manifests fully but leave clearly marked
placeholders and a short runbook note for what the user needs to fill in once each account
exists. Don't block other phases waiting on these.

## Repo layout to create

```
home-ops/
├── .tool-versions              # asdf: talosctl, talhelper, flux2, kubectl, helm
├── README.md
├── talos/
│   ├── talconfig.yaml
│   └── clusterconfig/
├── bootstrap/
│   └── kustomize/                # secret-zero push (op inject + kubectl apply), see Phase 3 below
├── kubernetes/
│   ├── flux/cluster/              # Flux's own bootstrap manifests + the one top-level sync
│   └── apps/                      # one tree grouped by K8s namespace, matching
│       │                          # onedr0p/home-ops and buroa/k8s-gitops (amended from the
│       │                          # original infrastructure/-vs-apps/ split)
│       ├── kube-system/           # cilium
│       ├── cert-manager/
│       ├── external-secrets/
│       ├── rook-ceph/
│       ├── networking/            # envoy-gateway, cloudflared, headscale-subnet-router,
│       │                          # gateway-api-crds
│       ├── observability/         # gatus (status page only for now -- kube-prometheus-stack +
│       │                          # Loki was too heavy for one 8GB node, see git history;
│       │                          # metrics-server lives under kube-system instead)
│       └── default/               # empty scaffolding for now: immich, home-assistant,
│                                   # jellyfin, paperless-ngx, homepage
├── .github/workflows/           # Renovate config, CI validation (kubeconform)
└── docs/runbooks/
    ├── cluster-bootstrap.md     # talosctl bootstrap step (the one manual step)
    └── secret-zero.md           # the op inject step (the other manual step)
```

## Implementation order

1. `.tool-versions`, repo init, `gh repo create alexmathieu22-ops/home-ops --public`
2. `talosctl cluster create` locally (Docker provisioner) as the dev target
3. `talos/talconfig.yaml` via talhelper, generate configs against the local cluster
4. `bootstrap/kustomize/external-secrets` — a `Secret` manifest referencing
   `op://home-ops/eso-service-account/token`, rendered via `op inject` and applied with
   `kubectl`, creating the `external-secrets` namespace + `onepassword-service-account-token`
   Secret. No-op with a clear error until 1Password exists and `op` is authenticated.
5. `flux bootstrap github --owner=alexmathieu22 --repository=home-ops --path=kubernetes/flux/cluster --personal`
6. Infrastructure HelmReleases in order: Cilium (with LB-IPAM/L2) → cert-manager →
   external-secrets → cloudflared → Rook-Ceph → Envoy Gateway
7. Headscale subnet router manifests (mark Headscale server hosting as pending/deferred)
8. Gatus (status page) + metrics-server
9. Empty app scaffolds for the apps listed above, ready to fill in once storage/DNS/secrets
   are live
10. Renovate config + a basic CI workflow (kubeconform validation on PR)

Work through this in order, committing at each working checkpoint rather than one giant
commit. Ask before any step that would need a real credential that hasn't been provided yet.
