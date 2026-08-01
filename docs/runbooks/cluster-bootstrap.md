# Runbook: cluster bootstrap

The one genuinely manual, non-GitOps step in this repo's lifecycle — same as it is for
every Talos cluster, local or real hardware. Run once per cluster (or after a full
disaster-recovery rebuild).

## Local dev cluster (current target — hardware not yet purchased)

```bash
sudo -E "$(asdf which talosctl)" cluster create qemu --name home-ops-dev --controlplanes 3 --workers 0
```

`sudo` is required on macOS for the QEMU/vmnet networking setup. This uses the real
Talos + Kubernetes QEMU provisioner (not Docker — the installed talosctl restructured
`cluster create` into subcommands and the `docker` one no longer supports multi-controlplane;
see git history for that decision). It generates machine configs, applies them, and
bootstraps etcd + Kubernetes automatically, waiting until the cluster is ready.

Merge the kubeconfig and confirm:

```bash
talosctl kubeconfig -n 10.5.0.2
kubectl get nodes
```

Tear down when done:

```bash
sudo -E "$(asdf which talosctl)" cluster destroy --name home-ops-dev
```

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
