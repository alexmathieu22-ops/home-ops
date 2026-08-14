# Implementation notes

Rationale and gotchas that used to live as long comments inside the YAML itself. Resource
files now carry only short pointers back here — this is the durable home for the "why."
Organized by area; each section maps to one or more paths under `kubernetes/` or `talos/`.

## Flux Kustomization pattern: split `ks.yaml` for CRD/CR races

Several components (`cilium`, `cert-manager`, `external-secrets`, `envoy-gateway`,
`rook-ceph`) define a resource that depends on a CRD installed by that same component's
own Helm chart — e.g. cert-manager's `ClusterIssuer` needs the CRD cert-manager itself
installs. A single Kustomization applying both at once races the CRD's own registration.
The fix, used consistently across this repo: each `ks.yaml` defines two Kustomizations —
the base component, then a `-config` (or `-cluster`) one that `dependsOn` the base and
applies just the CRs. `kubernetes/flux/cluster/sync.yaml` is the only Kustomization
defined centrally; everything else — namespace grouping, ordering, `dependsOn` — lives
colocated in each component's own `ks.yaml`, one apps tree grouped by K8s namespace
(matching onedr0p/home-ops and buroa/k8s-gitops's convention), no separate
`infrastructure/` vs `apps/` split.

`wait: true` + `healthCheckExprs` on these `-config` Kustomizations is deliberate, not a
bug to route around: several (cert-manager's `ClusterIssuer`, external-secrets'
`ClusterSecretStore`, cloudflared's tunnel token) genuinely can't go `Ready` until
1Password/Cloudflare accounts exist (see PROJECT_BRIEF.md's "Deferred by user" list) — a
`healthCheckExprs` block checks the resource's real `Ready`/`Programmed` condition
explicitly (Gateway API's `Programmed` isn't the generic `Ready` Flux auto-detects for
most CRDs) so staying not-Ready is an accurate signal, not a false green.

## Talos gotchas

- **kube-proxy disabled** (`cniConfig.name: none`, `cluster.proxy.disabled: true` in
  `talos/talconfig.yaml`): Cilium replaces it (kube-proxy-replacement mode).
- **cloudflared UDP buffer sysctls** (`net.core.rmem_max`/`wmem_max` in
  `talconfig.yaml`): cloudflared's QUIC transport needs bigger buffers than the kernel
  default — observed warning `wanted: 7168 kiB, got: 416 kiB`, causing periodic
  reconnects.
- **metrics-server `--kubelet-insecure-tls`**: Talos issues real, rotated kubelet certs
  (unlike kubeadm, which is why this flag isn't a general Talos requirement), but
  metrics-server's TLS validation against the kubelet commonly fails anyway because the
  cert's SANs don't reliably cover whichever address type metrics-server picks to
  connect on — a documented Talos+metrics-server gotcha (see
  docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/deploy-metrics-server).
  Connections stay TLS-encrypted, just not certificate-validated — acceptable for
  internal-only cluster metrics (`kubectl top`/k9s), not exposed outside the cluster.
- **local-path-provisioner needs `machine.kubelet.extraMounts`**: Talos's root
  filesystem is a read-only squashfs overlay — only `/var` (the EPHEMERAL partition)
  persists. local-path-provisioner's data path is repointed at
  `/var/local-path-provisioner`, and the kubelet only bind-mounts a fixed set of host
  paths into its own mount namespace by default, so `talconfig.yaml` adds an
  `extraMounts` patch (`source` == `destination`, both `/var/local-path-provisioner`) —
  without it, PVCs report a healthy StorageClass but fail to actually mount. This is a
  machine config change: re-apply it to the real node after it changes
  (`talhelper gencommand apply` or `talosctl apply-config`) — Flux can't push it. See
  also `docs/runbooks/cluster-bootstrap.md`'s "Known limitations running single-node".

## Storage: Rook-Ceph and the local-path-provisioner interim

Rook-Ceph's normal topology is a dedicated raw block device per node for OSDs — it only
claims genuinely free/unpartitioned space, so at worst it comes up with zero usable OSDs
(not destructive to the Talos install) rather than fighting the OS for its disk.
**Current real hardware** (HP ProDesk 600 G4 Mini) has one 256GB NVMe, entirely consumed
by the Talos install, zero spare block device — expect `rook-ceph-cluster`'s CephCluster
to sit unhealthy with 0 OSDs until a second disk is attached (the box's second, empty
M.2 slot is the cleanest option — see HARDWARE_PLAN.md, which doesn't currently budget
for it). Separately, `cephBlockPools` is `replicated.size: 3`: with a single node (and
likely a single OSD once one exists), Ceph can never place 3 replicas, so the pool stays
unhealthy even after adding one disk — not fixed yet since it doesn't block anything else
in the dependency chain. Either leave the Kustomization unreconciled until more nodes
exist, or drop `replicated.size` to `1` (data-loss risk, single point of failure) as a
deliberate, revisited-later tradeoff. `mon.allowMultiplePerNode: true` is required for
the local single-node dev cluster (Rook refuses to schedule 3 mons on fewer than 3 nodes
otherwise, permanently blocking the HelmRelease's `--wait`) and is harmless to also carry
into the real multi-node config. `mgr`/`mon`/`osd` resource requests are scaled well
below common upstream examples (often 8Gi+) to fit this hardware — revisit once real
usage is known (`ceph osd df`).

**Interim answer while Rook-Ceph has no usable OSDs:**
`kubernetes/apps/kube-system/local-path-provisioner` -- node-local hostPath storage
(single replica, no HA/replication/snapshots). Set as the cluster default `StorageClass`
(`local-path`); `ceph-block`'s `isDefault` is flipped to `false` in the same change,
since two default StorageClasses is invalid/ambiguous and `ceph-block` isn't usable yet
-- the two flip back together once real OSDs exist. This is explicitly an amendment, not
a replacement, of the Rook-Ceph decision in `PROJECT_BRIEF.md`'s decision table -- see
that file and `docs/runbooks/cluster-bootstrap.md`.

Deployed via bjw-s's `app-template` (`oci://ghcr.io/bjw-s-labs/helm/app-template`), not a
third-party community chart -- Rancher doesn't publish an official chart itself
(rancher/local-path-provisioner#89), and the alternatives are all single-maintainer
wrappers. RBAC (ClusterRole/ClusterRoleBinding/Role/RoleBinding), the `config.json`
node-path map, and the `StorageClass` itself are hand-written as `extraObjects`,
transcribed 1:1 from upstream's own raw deploy manifest
(rancher/local-path-provisioner `deploy/local-path-storage.yaml`) rather than depending
on anyone's packaging of it. Not yet live-verified against the real cluster -- confirm a
PVC actually binds after first reconcile.

## Networking: Gateway API split, AdGuard Home, cloudflared, Headscale

**Internal vs external Gateway** (`kubernetes/apps/networking/envoy-gateway/config/`):
matches onedr0p/home-ops's pattern. `internal` (`*.internal.alexandremathieu.com`, HTTP
+ HTTPS via a cert-manager `letsencrypt-dns01` cert) gets a Cilium LB-IPAM LoadBalancer
IP, reachable over the Headscale subnet router/VPN. `external`
(`*.alexandremathieu.com`, HTTP-only — Cloudflare terminates TLS at its own edge, and the
tunnel connection is already encrypted, so no cert-manager cert is needed) is forced to
`ClusterIP` via a custom `EnvoyProxy` resource referenced through
`Gateway.spec.infrastructure.parametersRef` — it only ever needs to be reached
in-cluster, by cloudflared, so a LoadBalancer would needlessly burn one of the few IPs in
Cilium's LB-IPAM pool and expose it on the LAN for no reason. cloudflared gets ONE static
public-hostname entry (`*.alexandremathieu.com` → the external Gateway's Service) instead
of one dashboard entry per app; every future public app is then just an `HTTPRoute`
addition (see `docs/runbooks/cloudflare-setup.md`). The Gateway API CRDs themselves
(`kubernetes/apps/networking/gateway-api-crds`) are a separate upstream project — neither
Cilium (CNI/LB-IPAM/L2 only) nor the Envoy Gateway Helm chart install them.

That static public-hostname entry and its wildcard DNS record are managed by
`terraform/cloudflare-tunnel`, not clicked in by hand — it references the tunnel (created
via `cloudflared tunnel create`) by ID rather than owning the tunnel resource itself, since
recreating that resource in Terraform would mint a new token and force re-wiring the
1Password item + a cloudflared rollout for no benefit. Same rationale as `terraform/headscale`
being its own root module rather than folded into one big `terraform/` state: independent
lifecycles, independent blast radius.

**AdGuard Home** (`kubernetes/apps/networking/adguard-home`): exists purely to make the
internal Gateway's wildcard hostname resolvable -- the ISP-provided router has no
local-DNS-record capability at all (confirmed against the vendor's own docs). Deliberately not
the house's only DNS server end-to-end: set this pod's LoadBalancer IP as the *primary*
DHCP DNS server on the router with a public resolver (e.g. 1.1.1.1) as *secondary* -- if
the pod is ever down, general internet DNS falls back automatically (most OS resolvers
retry the secondary on timeout); only `*.internal.alexandremathieu.com` stops resolving.
That's the deliberately accepted blast radius for running this on the single node instead
of a dedicated always-on device. No persistence yet (same tradeoff as Gatus, see
Observability below, but with a sharper consequence): AdGuard's first-run admin account
setup would be written into the same config file this HelmRelease seeds from git, so a
pod restart wipes that account and the setup wizard has to be redone -- the DNS behavior
itself (rewrite + upstream) reliably re-seeds from git regardless. Flip on persistence
once `local-path` (or `ceph-block`) is confirmed working. The rewrite target IP
(`192.168.18.CHANGEME`) needs the internal Gateway's actual assigned IP once known
(`kubectl get gateway -n networking internal` -- Cilium LB-IPAM auto-assigns from the
pool, not knowable ahead of time).

Deployed via bjw-s's `app-template`, not the gabe565 community chart previously used --
gabe565's chart is itself just a per-app wrapper around app-template's own common
library, single-maintainer, and already caused one bug (assumed web port 80, actual
default 3000). Going straight to app-template means owning the pod spec directly (image,
ports, probes, an initContainer that copies the git-sourced config into a writable
`emptyDir`, since AdGuard needs to write back to its config file at runtime) with no
third-party packaging opinion in between -- matches onedr0p/buroa's actual convention for
apps without an official upstream chart. `route.main` in the HelmRelease values (keyed to
match `service.main`) generates the HTTPRoute directly -- no standalone `httproute.yaml`,
no guessing the rendered Service's name for a backendRef (same pattern as Gatus, and the
fix for an inconsistency between the two that wasn't caught until asked about directly).
Not yet live-verified: probe behavior needs a `kubectl get pods -n networking` check
after first reconcile.

**Headscale subnet router** (`kubernetes/apps/vpn/headscale-subnet-router`): plain
Tailscale client advertising the home LAN CIDR into the tailnet — not the Tailscale
Kubernetes Operator, which is incompatible with self-hosted Headscale (only implements
Tailscale's v1 API; see juanfont/headscale#3081, #3086). `TS_KUBE_SECRET=""` disables
containerboot's default of writing state to a Secret (which takes precedence over
`TS_STATE_DIR` on Kubernetes), keeping state only on the pod's own PVC and avoiding extra
RBAC. `TS_LOGIN_SERVER` is not a real containerboot env var (confirmed against current
`cmd/containerboot` source — it's silently ignored, which is why this was connecting to
Tailscale's own coordination server instead of Headscale); `--login-server` has to go
through `TS_EXTRA_ARGS` instead. No `--advertise-tags`: Headscale rejects any tag not
pre-declared as owned in an ACL policy, and none is configured yet. The `vpn` namespace
is split out from `networking` specifically to scope its permissive PodSecurity labels
(this workload needs `NET_ADMIN`/`NET_RAW` and a hostPath `/dev/net/tun` mount) to only
the workload that needs them.

**Flux GitHub webhook** (`kubernetes/apps/flux-system/webhooks`): a notification-controller
`Receiver` (type `github`) so a push reconciles immediately instead of waiting out the
`GitRepository`'s 1-minute poll — matches onedr0p/home-ops and buroa/k8s-gitops. The
`Receiver`'s `resources` list only needs the `GitRepository`, not every downstream
`Kustomization`: kustomize-controller already watches it for revision changes, so anything
sourced from it reconciles right after. Routed through the same `external` Gateway +
cloudflared tunnel as any other public app (`webhook-receiver`, a separate Service from
notification-controller's own — see `gotk-components.yaml` — on its dedicated
`http-webhook` port). Manual GitHub-side step (token generation, webhook creation) is
`docs/runbooks/flux-webhook.md`, same shape as `cloudflare-setup.md`'s public-hostname step.

## Secrets: 1Password SDK provider

`ClusterSecretStore` uses ESO's `onepasswordSDK` provider (not the older Connect-based
`onepassword` provider, not 1Password Connect server or Vaultwarden — see
PROJECT_BRIEF.md's decision table). Its `remoteRef.key` format is
`<item>/[section/]<field>`, with no separate `property` field — different from other ESO
providers. Double check the exact field shape against the installed ESO chart's CRD if
reconciliation fails; this provider surface is newer than a given knowledge cutoff can
fully guarantee.

## Observability: Gatus instead of kube-prometheus-stack + Loki

kube-prometheus-stack + Loki + Alloy (what onedr0p/buroa actually run) targets
multi-node clusters with real RAM headroom; on this single 8GB node it competed with
Cilium/cert-manager/external-secrets/apps for the same tight budget. Gatus alone covers
"is everything up" without that cost. Whether to add real metrics/logs later
(self-hosted once node 2 exists, or Grafana Cloud's free tier) is an open decision, not
made here. No persistence yet: uptime history resets on pod restart, acceptable for an
"is it up right now" status page. Flip on once storage is viable.

Deployed via bjw-s's `app-template` (matching AdGuard Home/local-path-provisioner),
adapted from buroa/k8s-gitops's Gatus setup rather than the `twin` chart used before --
comparison requested and confirmed against buroa's actual file. The interesting piece is
`gatus-sidecar` (`ghcr.io/home-operations/gatus-sidecar`, onedr0p's org), run as a native
sidecar (`initContainers` + `restartPolicy: Always`, not a one-shot init step): it watches
HTTPRoutes cluster-wide and auto-writes a `gatus-sidecar.yaml` endpoint list, which Gatus
merges with our own hand-written `config.yaml` (Gatus's `GATUS_CONFIG_PATH` can point at a
directory -- every `*.yaml` inside gets merged, arrays appended not overwritten, then
hot-reloaded, no pod restart needed) -- replaces manually maintaining `config.endpoints`
for every app. `--gateway-name` is set to both `external` and `internal` (buroa only
watches their public gateway) since this status page's job is general "is anything down"
awareness, not just public uptime; narrow it to just `external` if a public status page
shouldn't reveal internal-only app names. Apps opt out via the
`gatus.home-operations.com/enabled: "false"` annotation on their HTTPRoute -- used on
Gatus's own route so it doesn't monitor itself. `gatus-sidecar`'s ClusterRole is scoped
to just `httproutes`/`gateways` (not the Ingress/Service/Traefik IngressRoute permissions
its own upstream RBAC example grants, since this repo uses none of those). Not adopted
from buroa: the Prometheus ServiceMonitor (no Prometheus Operator CRDs here), the
Stakater Reloader annotation (not installed), and the alerting `envFrom` secretRef (no
Gatus alerting integration configured yet). Image tags pinned to an exact version
(`v5.36.0`/`0.4.0`, both current as of implementation) rather than a floating range, but
without a digest -- unlike buroa's `@sha256:...` pins, which weren't independently
verifiable from here.
