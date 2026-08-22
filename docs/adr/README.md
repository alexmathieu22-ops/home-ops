# Architecture Decision Records

Rationale and gotchas for decisions made in this repo, one file per decision. Previously
lived as one long `IMPLEMENTATION_NOTES.md`; split out so each decision can be linked to
directly from the code it explains.

- [0001. Split `ks.yaml` into two Kustomizations to avoid CRD/CR races](0001-split-ks-yaml-for-crd-cr-races.md)
- [0002. Disable kube-proxy in favor of Cilium's replacement](0002-disable-kube-proxy-for-cilium.md)
- [0003. Raise UDP buffer sysctls for cloudflared's QUIC transport](0003-cloudflared-udp-buffer-sysctls.md)
- [0004. Run metrics-server with `--kubelet-insecure-tls`](0004-metrics-server-kubelet-insecure-tls.md)
- [0005. Add `machine.kubelet.extraMounts` for local-path-provisioner](0005-local-path-provisioner-extra-mounts.md)
- [0006. Rook-Ceph hardware topology, `replicated.size`, and the local-path-provisioner interim](0006-rook-ceph-topology-and-local-path-interim.md)
- [0007. Disable Rook-managed PDBs to unblock node drains](0007-rook-ceph-node-drains-and-pdbs.md)
- [0008. Mute permanent Rook-Ceph health warnings; rotate daemon keys for CVE-2025-30156](0008-rook-ceph-muted-health-warnings.md)
- [0009. Expose Home Assistant via a plain LoadBalancer Service](0009-home-assistant-loadbalancer-exposure.md)
- [0010. Extend Home Assistant's HelmRelease timeout to 10m](0010-home-assistant-extended-timeout.md)
- [0011. Lenient liveness/startup, strict readiness only, `/` instead of `/healthz`](0011-home-assistant-probe-strategy.md)
- [0012. Keep Home Assistant's `.venv` on scratch/`emptyDir`, not the persistent PVC](0012-home-assistant-venv-on-emptydir.md)
- [0013. Split Gateway API into internal and external Gateways](0013-gateway-api-internal-external-split.md)
- [0014. Run AdGuard Home for internal DNS resolution (deferred)](0014-adguard-home-internal-dns-deferred.md)
- [0015. Run a plain Tailscale client as a Headscale subnet router](0015-headscale-subnet-router.md)
- [0016. Add a Flux GitHub webhook receiver for immediate reconcile](0016-flux-github-webhook-receiver.md)
- [0017. Use ESO's 1Password SDK provider for secrets](0017-1password-sdk-secret-provider.md)
- [0018. Run Gatus instead of kube-prometheus-stack + Loki](0018-gatus-instead-of-prometheus-loki.md)
