# Architecture Decision Records

Rationale and gotchas for decisions made in this repo, one file per decision, grouped
into subdirectories by area and named by the date the decision was made. Previously
lived as one long `IMPLEMENTATION_NOTES.md`; split out so each decision can be linked to
directly from the code it explains.

## Flux

- [2026-08-02. Split `ks.yaml` into two Kustomizations to avoid CRD/CR races](flux/2026-08-02-split-ks-yaml-for-crd-cr-races.md)

## Talos

- [2026-08-01. Disable kube-proxy in favor of Cilium's replacement](talos/2026-08-01-disable-kube-proxy-for-cilium.md)
- [2026-08-02. Raise UDP buffer sysctls for cloudflared's QUIC transport](talos/2026-08-02-cloudflared-udp-buffer-sysctls.md)
- [2026-08-13. Run metrics-server with `--kubelet-insecure-tls`](talos/2026-08-13-metrics-server-kubelet-insecure-tls.md)
- [2026-08-13. Add `machine.kubelet.extraMounts` for local-path-provisioner](talos/2026-08-13-local-path-provisioner-extra-mounts.md)

## Storage

- [2026-08-19. Rook-Ceph hardware topology, `replicated.size`, and the local-path-provisioner interim](storage/2026-08-19-rook-ceph-topology-and-local-path-interim.md)
- [2026-08-19. Disable Rook-managed PDBs to unblock node drains](storage/2026-08-19-rook-ceph-node-drains-and-pdbs.md)
- [2026-08-19. Mute permanent Rook-Ceph health warnings; rotate daemon keys for CVE-2025-30156](storage/2026-08-19-rook-ceph-muted-health-warnings.md)

## Home Assistant

- [2026-08-14. Expose Home Assistant via a plain LoadBalancer Service](home-assistant/2026-08-14-home-assistant-loadbalancer-exposure.md)
- [2026-08-14. Extend Home Assistant's HelmRelease timeout to 10m](home-assistant/2026-08-14-home-assistant-extended-timeout.md)
- [2026-08-14. Lenient liveness/startup, strict readiness only, `/` instead of `/healthz`](home-assistant/2026-08-14-home-assistant-probe-strategy.md)
- [2026-08-14. Keep Home Assistant's `.venv` on scratch/`emptyDir`, not the persistent PVC](home-assistant/2026-08-14-home-assistant-venv-on-emptydir.md)

## Networking

- [2026-08-16. Split Gateway API into internal and external Gateways](networking/2026-08-16-gateway-api-internal-external-split.md)
- [2026-08-13. Run AdGuard Home for internal DNS resolution (deferred)](networking/2026-08-13-adguard-home-internal-dns-deferred.md)
- [2026-08-01. Run a plain Tailscale client as a Headscale subnet router](networking/2026-08-01-headscale-subnet-router.md)
- [2026-08-13. Add a Flux GitHub webhook receiver for immediate reconcile](networking/2026-08-13-flux-github-webhook-receiver.md)

## Secrets

- [2026-08-01. Use ESO's 1Password SDK provider for secrets](secrets/2026-08-01-1password-sdk-secret-provider.md)

## Observability

- [2026-08-13. Run Gatus instead of kube-prometheus-stack + Loki](observability/2026-08-13-gatus-instead-of-prometheus-loki.md)
- [2026-08-22. Add a minimal Prometheus (kube-prometheus-stack) to feed kromgo's README badges](observability/2026-08-22-minimal-prometheus-for-kromgo.md)
