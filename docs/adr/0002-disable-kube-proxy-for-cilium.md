# 0002. Disable kube-proxy in favor of Cilium's replacement

## Status

Accepted

## Context

Talos can run with or without kube-proxy. Cilium can fully replace kube-proxy
(kube-proxy-replacement mode), and running both is redundant.

## Decision

`cniConfig.name: none` and `cluster.proxy.disabled: true` in `talos/talconfig.yaml`
disable kube-proxy; Cilium replaces it.

## Consequences

Cilium is solely responsible for Service routing cluster-wide — any Service-routing
issue should be debugged against Cilium's kube-proxy-replacement mode, not kube-proxy.
