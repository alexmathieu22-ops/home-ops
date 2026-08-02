# Runbook: cluster bootstrap

The one genuinely manual, non-GitOps step in this repo's lifecycle — same as it is for
every Talos cluster, local or real hardware. Run once per cluster (or after a full
disaster-recovery rebuild).

## Local dev cluster (current target — hardware not yet purchased)

```bash
talosctl cluster create docker --name home-ops-dev --workers 0
```

Single control-plane, no `sudo` needed. It generates machine configs, applies them, and
bootstraps etcd + Kubernetes automatically, merging the kubeconfig into `~/.kube/config`.

Confirm:

```bash
kubectl get nodes
```

Tear down when done:

```bash
talosctl cluster destroy --name home-ops-dev
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

## Real hardware (once the 3x Beelink EQ12 Pro nodes exist)

1. Flash the Talos ISO to USB (or PXE-boot) for each node; boot all 3.
2. Discover them on the LAN:
   ```bash
   nmap -Pn -n -p 50000 192.168.1.0/24 -vv | grep Discovered
   ```
3. Update `talos/talconfig.yaml` — swap the `nodes:` block's hostnames/IPs for the real
   LAN addresses and `installDisk` for the real NVMe device (e.g. `/dev/nvme0n1`).
   Everything else (CNI disabled, `allowSchedulingOnControlPlanes`, kube-proxy disabled)
   stays as-is.
4. Generate secrets once, keep them local (never committed — this repo uses zero SOPS):
   ```bash
   cd talos
   talhelper gensecret > talsecret.yaml
   ```
5. Generate and apply configs:
   ```bash
   talhelper genconfig
   talhelper gencommand apply | bash
   ```
6. Bootstrap etcd on one control-plane node:
   ```bash
   talosctl bootstrap -n <first-node-ip>
   ```
7. Pull kubeconfig, confirm nodes are `Ready`:
   ```bash
   talosctl kubeconfig -n <first-node-ip>
   kubectl get nodes
   ```

After this, [Flux bootstrap](../../PROJECT_BRIEF.md) takes over — everything else is
`git push`.
