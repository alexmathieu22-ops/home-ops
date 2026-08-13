# Runbook: cluster bootstrap

The one genuinely manual, non-GitOps step in this repo's lifecycle — same as it is for
every Talos cluster, local or real hardware. Run once per cluster (or after a full
disaster-recovery rebuild).

## Local dev cluster (current target — hardware not yet purchased)

```bash
talosctl cluster create docker --name home-ops-dev --workers 0 --memory-controlplanes 6GB \
  --config-patch '{"cluster":{"network":{"cni":{"name":"none"}},"proxy":{"disabled":true}}}'
```

Single control-plane, no `sudo` needed. `--memory-controlplanes 6GB` matters: the default
2GB is too tight once Flux and a few HelmReleases are running and causes controller crash
loops. The `--config-patch` disables Talos's default Flannel/kube-proxy the same way
`talos/talconfig.yaml` does for real hardware — without it Cilium and Flannel fight over
the same pod network and everything (including Flux's own controllers) gets flaky
"no route to host" errors. This merges the kubeconfig into `~/.kube/config`. The node
comes up `NotReady` and `coredns` stays `Pending` until Cilium exists — expected, see the
next step.

Remove the default control-plane taint so a single-node cluster can actually schedule
workloads (real hardware has dedicated capacity across 3 nodes; the throwaway local
cluster doesn't):

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
```

This has been observed to reappear once, shortly after, when kubelet does its first
config resync — if `flux-system` pods (or anything else) go `Pending` with "untolerated
taint" shortly after this step, just re-run the same `kubectl taint` command once more.

### Install Cilium (before Flux)

```bash
helmfile -f bootstrap/helmfile/helmfile.yaml sync
```

Talos's CNI is disabled (`talos/talconfig.yaml`: `cniConfig.name: none`), so nothing —
including Flux's own controller pods — can get pod networking without Cilium first. This
installs it directly via Helm, reading chart/values straight from the committed
`kubernetes/apps/kube-system/cilium/app/helmrelease.yaml` (never duplicated — see
`bootstrap/helmfile/helmfile.yaml`'s comment). Flux takes over reconciling this exact
release once it exists; `helm upgrade` against an already-installed release converges
safely. Run this once per cluster lifetime, same as `talosctl bootstrap`.

Confirm:

```bash
kubectl get nodes
```

Tear down when done:

```bash
talosctl cluster destroy --name home-ops-dev
```

Destroying and recreating repeatedly (e.g. while iterating on this repo) accumulates
stale `talosctl`/`kubectl` contexts — `talosctl cluster create` renames the previous
`home-ops-dev` context out of the way instead of overwriting it if one already exists,
and `kubectl`'s current-context pointer can end up referencing a user/cluster entry that
no longer resolves cleanly. If `kubectl`/`talosctl` start failing with auth or "cannot
locate user" errors that don't match the cluster's actual state, this is almost always
why — clean up before recreating:

```bash
talosctl config contexts   # remove any home-ops-dev* entries via `talosctl config remove`
kubectl config get-contexts  # delete stale home-ops-dev* contexts/clusters/users via `kubectl config delete-*`
```

### Why Docker, not QEMU

`talosctl cluster create qemu --controlplanes 3 --workers 0` would give a real 3-CP HA
cluster locally, closer to the eventual hardware topology. It doesn't work on this
machine: QEMU with `hvf` acceleration on Apple Silicon hits a kexec hang right after
install (`machined` stops producing any output, the Talos API on port 50000 never comes
up) — a known, currently-unresolved upstream regression,
[siderolabs/talos#13108](https://github.com/siderolabs/talos/issues/13108). It also
requires `sudo`, which leaves `~/.talos` and generated kubeconfig files root-owned and
awkward to use afterward.

Docker sidesteps the whole problem — no VM boot, no kexec, no root — at the cost of only
getting a single control-plane node, so etcd HA and multi-node scheduling can't be
exercised locally. If the upstream kexec bug gets fixed, revisit: QEMU is the more
faithful topology, and this repo's `talos/talconfig.yaml` already describes the real
3-node target.

## Real hardware — single node (current: HP ProDesk 600 G4 Mini)

Current setup: a single HP ProDesk 600 G4 Mini (i5-8500T, 8GB RAM, 256GB SSD), run
standalone — the steps below cover bringing up that one node. `talos/talconfig.yaml`'s
`nodes:` block has this one entry; when more nodes arrive later, append to that block and
re-run `talhelper genconfig`/`gencommand apply` for the new node(s) only — everything
below still applies unchanged for a single node.

1. **Build a custom Talos ISO via the Image Factory** with the four system extensions
   listed under "System extensions" below: `siderolabs/intel-ucode`, `siderolabs/i915`,
   `siderolabs/nfs-utils`, `siderolabs/nut-client`. Two aren't useful yet (no NAS, no UPS
   yet), but they cost nothing to bake in now versus a `talosctl upgrade` later. Easiest
   via the UI — go to [factory.talos.dev](https://factory.talos.dev/), pick `v1.13.8`,
   check those four extensions, and it gives you a download link and a schematic ID. Or
   via CLI:
   ```bash
   schematic_id=$(curl -sS -X POST --data-binary @- https://factory.talos.dev/schematics <<'YAML' | jq -r .id
   customization:
     systemExtensions:
       officialExtensions:
         - siderolabs/intel-ucode
         - siderolabs/i915
         - siderolabs/nfs-utils
         - siderolabs/nut-client
   YAML
   )
   echo "https://factory.talos.dev/image/${schematic_id}/v1.13.8/metal-amd64.iso"
   ```
   Future `talosctl upgrade`s need to reference
   `factory.talos.dev/installer/<schematic-id>:<version>` rather than a plain version tag,
   since the extensions live in that image — so the schematic ID is recorded here:

   ```
   schematic ID: efa30a61a77a39580af45a52c5bc42b3830d9a6c760973da63cdb88cd750502a
   ISO:          https://factory.talos.dev/image/efa30a61a77a39580af45a52c5bc42b3830d9a6c760973da63cdb88cd750502a/v1.13.8/metal-amd64.iso
   ```
2. **Flash it to a USB stick** — [balenaEtcher](https://etcher.balena.io/) or Rufus, or
   from the Mac terminal:
   ```bash
   diskutil list                       # find the USB stick's /dev/diskN — DOUBLE CHECK, this is destructive
   diskutil unmountDisk /dev/diskN
   sudo dd if=metal-amd64.iso of=/dev/rdiskN bs=4m status=progress
   ```
3. **Boot the ProDesk from USB**: plug the stick into it, power on, tap **F9** repeatedly
   during the HP logo screen for the boot menu (F10 gets you into BIOS setup instead, in
   case you need it). If it won't boot the USB at all, check BIOS setup: this is an
   8th-gen business desktop, so **Secure Boot is likely enabled by default** — Talos's
   plain ISO isn't Secure Boot-signed, so either disable Secure Boot (BIOS → Security →
   Secure Boot → Disable) or use a
   [Secure Boot-signed image](https://www.talos.dev/v1.13/talos-guides/install/bare-metal-platforms/secureboot/)
   from the Image Factory instead. Also confirm Boot Mode is UEFI (not Legacy/CSM).
4. Talos boots into **maintenance mode** (no disk touched yet) and gets a DHCP address —
   check the console screen directly, Talos prints the assigned IP in the boot banner.
   Real LAN here turned out to be `192.168.18.0/24`, not `192.168.1.0/24` (that was an
   unconfirmed placeholder used throughout this repo until now — if `nmap`/router UI
   don't turn anything up on `192.168.1.0/24`, that's why; adjust the subnet below to
   match your own network):
   ```bash
   nmap -Pn -n -p 50000 192.168.18.0/24 -vv | grep Discovered
   ```
5. **Reserve that IP** as a static DHCP reservation in your router, bound to the box's
   MAC address — simpler than embedding static network config in the Talos machine
   config, and survives reinstalls. Router UI showing "IPv4: Unknown" for the device
   doesn't block this — most routers let you create the reservation by MAC address alone,
   typing in the IP directly. This node's reserved IP is `192.168.18.39`, already set as
   `ipAddress` in `talos/talconfig.yaml` — use it as `<node-ip>` in the steps below.
6. **Check the actual disk device name** while still in maintenance mode:
   ```bash
   talosctl get disks -n <node-ip> --insecure
   ```
   Confirmed: the SSD is `/dev/nvme0n1` (256GB, Toshiba KBG30ZMV256G) — the only other
   disk listed is the 16GB USB install stick itself (`/dev/sda`). `talconfig.yaml` uses
   `installDiskSelector: {size: ">= 100GB"}` rather than hardcoding the NVMe path, which
   correctly picks the SSD and excludes the USB stick either way.
7. Generate secrets once, then encrypt them for git — this is the one exception to
   "zero SOPS" in this repo (see `.sops.yaml`'s comment for why: Talos secrets have to
   exist before the cluster/ESO does, so 1Password + ESO can't cover them the way every
   other secret in this repo is covered):
   ```bash
   cd talos
   talhelper gensecret > talsecret.yaml
   sops encrypt talsecret.yaml > talsecret.sops.yaml
   ```
   Commit `talsecret.sops.yaml` — that's the encrypted one, safe for git (`.gitignore`
   still excludes the plaintext `talsecret.yaml`). `talhelper` decrypts
   `talsecret.sops.yaml` transparently in the next step, as long as the age private key
   at `~/Library/Application Support/sops/age/keys.txt` exists locally. That key is the
   one thing in this whole flow that can't be regenerated or recovered from Git if lost
   — back it up somewhere durable (1Password recommended, matching the rest of this
   repo's secrets tooling).
8. Generate and apply configs. The node is still in Talos's maintenance mode at this
   point (booted from the ISO, self-signed cert, no config applied yet), so the initial
   apply must skip TLS verification — `talhelper gencommand apply` doesn't do this by
   default (only `--extra-flags` gets passed through to the underlying `talosctl
   apply-config`), so pass `--insecure` explicitly or you'll hit `x509: certificate
   signed by unknown authority`:
   ```bash
   talhelper genconfig
   talhelper gencommand apply --extra-flags "--insecure" | bash
   ```
   This installs Talos to disk and reboots the node — pull the USB stick once it reboots.
   (Once the node has a real config applied, it's provisioned with the cluster's own PKI
   from `talsecret.sops.yaml` — later commands like `bootstrap`/`kubeconfig` below talk to
   it securely, no `--insecure` needed again for this node.)
9. Merge the generated talosconfig into your default `~/.talos/config` so bare
   `talosctl` commands (no `--talosconfig` flag) work from here on:
   ```bash
   talosctl config merge ./clusterconfig/talosconfig
   ```
   This adds the real cluster as a named context alongside the local dev cluster's
   context (from `talosctl cluster create docker` above) rather than overwriting it, and
   switches your *current* context to it. Skip this and every bare `talosctl` command
   below (including the next one) will fail with
   `x509: certificate signed by unknown authority` — it's not a cert problem, it just
   means the default context still points at the dev cluster's CA. If you ever need to
   flip back to the dev cluster: `talosctl config context home-ops-dev` (run
   `talosctl config contexts` to see exact names).
10. Bootstrap etcd (single-node, so there's no quorum to wait on, but the step is still
    required — Talos never bootstraps itself):
    ```bash
    talosctl bootstrap -n <node-ip>
    ```
11. Pull kubeconfig:
    ```bash
    talosctl kubeconfig -n <node-ip>
    ```
12. Install Cilium before anything else (same reasoning as the local dev cluster above —
    nothing gets pod networking without it, including Flux's own controllers):
    ```bash
    helmfile -f bootstrap/helmfile/helmfile.yaml sync
    ```
13. Confirm the node is `Ready`:
    ```bash
    kubectl get nodes
    ```

## Flux bootstrap

After the node is `Ready` and Cilium is up, this is the last manual step — from here on,
everything else in the cluster reconciles on `git push`. Run once per cluster (same
lifetime as `talosctl bootstrap` — not needed again except when adding a node or after a
full disaster-recovery rebuild).

If you were previously developing against the local Docker dev cluster (see "Local dev
cluster" above), tear it down and make sure your current `kubectl`/`talosctl` context
points at the real cluster first — `flux bootstrap` targets whatever context is currently
active, and there's no prompt/confirmation if it's the wrong one:

```bash
talosctl cluster destroy --name home-ops-dev
kubectl config get-contexts        # confirm which context is current
kubectl config use-context home-ops   # switch if needed — name matches clusterName in talconfig.yaml
talosctl config context home-ops      # same idea for talosctl
```

Generate a GitHub PAT for the bootstrap command itself — a fine-grained token scoped to
just this repo is the least-privilege option (`alexmathieu22/home-ops` under GitHub →
Settings → Developer settings → Personal access tokens → Fine-grained tokens):

- **Contents** → Read and write (Flux pushes the bootstrap manifests)
- **Administration** → Read and write (creates the deploy key Flux syncs with — and if a
  deploy key from a previous bootstrap already exists on the repo, e.g. from an earlier
  local dev cluster bootstrap, Flux needs to `DELETE` it before registering the new one;
  Read-only fails that step with `403: Resource not accessible by personal access token`)
- **Metadata** → Read-only (GitHub sets this automatically)

A short expiration (a day or two) is fine and good practice — Flux only uses this token
during the `bootstrap` command itself, to create a deploy key and push the initial
commits. Every reconciliation after that uses Flux's own SSH deploy key, not this PAT, so
there's no need to keep it valid or reuse it. You'll just generate a fresh one next time
you run `flux bootstrap` (new node, or DR rebuild).

```bash
export GITHUB_TOKEN=<paste the token>
flux bootstrap github --owner=alexmathieu22 --repository=home-ops --path=kubernetes/flux/cluster --personal
```

Confirm it's reconciling:

```bash
flux get kustomizations -A
kubectl get pods -A
```

`external-secrets` and anything depending on it (cert-manager's Cloudflare token, etc.)
will sit unhealthy until [`docs/runbooks/secret-zero.md`](secret-zero.md) is run against
this cluster too.

### Known limitations running single-node

- **No etcd HA** — one node is a single point of failure by definition; this is expected
  for now, not a bug. Revisit once node 2/3 exist.
- **Rook-Ceph will come up with zero usable OSDs** — the 256GB disk is entirely consumed
  by the Talos/OS install, so there's no raw block device left for Ceph. See the caveat
  comment in `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml`. Either leave
  Rook-Ceph's `Kustomization` unreconciled until you add a second disk (the box's second,
  empty M.2 slot is the cleanest option — see HARDWARE_PLAN.md), or accept it staying
  unhealthy for now — it won't block anything else in the dependency chain.
- **8GB RAM is tight.** Watch for OOM/crash-looping controllers once Cilium,
  cert-manager, external-secrets, and observability are all running together. The
  ProDesk 600 G4 Mini takes 2x DDR4 SODIMM up to 32GB; a RAM upgrade is a cheap,
  low-effort fix if you hit this before adding node 2.

### System extensions

Baked into the custom ISO from step 1, all four from the initial install rather than
added piecemeal later — cheaper to include now than to build a new schematic and
`talosctl upgrade` to it afterward:

- **`siderolabs/intel-ucode`** — Intel CPU microcode (Spectre/Meltdown-class mitigations
  and stability fixes). Useful immediately.
- **`siderolabs/i915`** — driver for the i5-8500T's UHD Graphics 630 iGPU, needed for
  Jellyfin hardware transcoding (Quick Sync) — see HARDWARE_PLAN.md's note on this being
  a genuine upside of this particular CPU. Not used until Jellyfin is deployed; loading
  the driver for hardware that exists is harmless either way. When Jellyfin actually
  goes in, its pod spec also needs `resources.limits: {gpu.intel.com/i915: 1}` plus the
  Intel GPU device plugin — a Kubernetes-side task, separate from the extension itself.
- **`siderolabs/nfs-utils`** (+ `nfsrahead`) — for mounting the planned NAS for bulk
  media once it exists (see HARDWARE_PLAN.md). Idle until then.
- **`siderolabs/nut-client`** — for monitoring a UPS once one's added (recommended
  regardless of tier, per HARDWARE_PLAN.md, to protect etcd from unclean shutdowns).
  Idle until then.

Everything else in the Image Factory's extension list doesn't apply to this box or this
stack — no AMD/Nvidia GPU, no enterprise NIC vendors, no ZFS/Btrfs/mdadm (Rook-Ceph is
the storage decision), no alternate VPN mesh or container runtime, nothing iSCSI-specific
(Rook-Ceph doesn't need `iscsi-tools`, that's only for iSCSI-backed CSI drivers), and
cloudflared/tailscale specifically stay as in-cluster workloads (already deployed that
way under `kubernetes/apps/`) rather than OS-level extensions — matches how reference
homelab repos (onedr0p/home-ops, buroa/k8s-gitops) run them too, so they're managed by
Flux like everything else instead of requiring a Talos image rebuild to change.

### Scaling to more nodes later

Append the new node(s) to `talos/talconfig.yaml`'s `nodes:` block (same shape as the
existing entry — hostname, reserved IP, disk selector, `controlPlane: true` to match the
existing "all nodes are control-plane" decision), then:

```bash
cd talos
talhelper genconfig
# brand-new nodes are in maintenance mode (need --insecure); nodes that already have a
# config and are just picking up a change don't. Safe to include either way since
# talhelper only generates apply-config for nodes whose config actually changed:
talhelper gencommand apply --extra-flags "--insecure" | bash
```

No `talosctl bootstrap` needed again — that's a once-per-cluster-lifetime step, already
done. New control-plane nodes join etcd automatically once their config is applied.
