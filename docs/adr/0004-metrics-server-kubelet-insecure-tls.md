# 0004. Run metrics-server with `--kubelet-insecure-tls`

## Status

Accepted

## Context

Talos issues real, rotated kubelet certs (unlike kubeadm, which is why this flag isn't a
general Talos requirement), but metrics-server's TLS validation against the kubelet
commonly fails anyway because the cert's SANs don't reliably cover whichever address type
metrics-server picks to connect on. This is a documented Talos+metrics-server gotcha (see
[docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/deploy-metrics-server](https://docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/deploy-metrics-server)).

## Decision

Run metrics-server with `--kubelet-insecure-tls`.

## Consequences

Connections stay TLS-encrypted, just not certificate-validated — acceptable for
internal-only cluster metrics (`kubectl top`/k9s), not for anything exposed outside the
cluster.
