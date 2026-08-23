# Add a minimal Prometheus (kube-prometheus-stack) to feed kromgo's README badges

Date: 2026-08-22

## Status

Accepted

## Context

The README header wanted live cluster badges (node count, CPU/memory usage, component
versions) via [kromgo](https://github.com/home-operations/kromgo). Kromgo isn't standalone: every
badge is a PromQL query, so it requires a real Prometheus to query. This repo has
[docs/adr/observability/2026-08-13-gatus-instead-of-prometheus-loki.md](2026-08-13-gatus-instead-of-prometheus-loki.md),
which explicitly ran Gatus instead of kube-prometheus-stack + Loki because "on this
single 8GB node it competed with Cilium/cert-manager/external-secrets/apps for the same
tight budget" -- while leaving the door open: "Whether to add real metrics/logs later
(self-hosted once node 2 exists, ...) is an open decision, not made here." `home-ops-2`
now exists, which is that ADR's own stated trigger.

## Decision

Add `kube-prometheus-stack`, but only the slice kromgo actually needs: Prometheus +
kube-state-metrics + node-exporter. Explicitly disabled: Grafana (no dashboards needed,
badges are the whole point), Alertmanager (nothing alerts on it yet -- also means
dropping kromgo's own "Alerts" badge, since that queries `alertmanager_alerts`),
`kubeProxy` monitoring (Cilium replaces kube-proxy, nothing to scrape --
[docs/adr/talos/2026-08-01-disable-kube-proxy-for-cilium.md](../talos/2026-08-01-disable-kube-proxy-for-cilium.md)),
and `defaultRules.create` (the chart's ~40 bundled alerting `PrometheusRule` objects --
useless with no Alertmanager to act on them, and each one is validated through
`prometheusOperator`'s admission webhook on install/upgrade; a burst of them landing
before that webhook's self-signed cert finishes syncing produced a string of `remote
error: tls: bad certificate` log lines on first install -- transient and harmless, but
removing the unused rules removes that noise too).
Prometheus itself: `replicas: 1`, `retention: 6h`, `storageSpec: {}` (ephemeral,
`emptyDir`) -- kromgo only ever queries the *current* value, never history, so losing
Prometheus's own data on a pod restart is a non-issue; a PVC isn't even an option yet
regardless, since Rook-Ceph still has 0 usable OSDs (see README Stack table). Small
explicit resource requests/limits on every component (Prometheus, the operator,
kube-state-metrics, node-exporter), same discipline as every other HelmRelease in this
repo.

Kromgo's badge list is trimmed down: no `Power` (no PDU/UPS exporter here), no `Alerts`
(see above), no `buddy_*` status-page badges (those track a multi-person "is my friend's
stuff up" status page, not applicable solo). Kept: Talos, Kubernetes, Flux, Nodes, Pods,
CPU, Memory, Age, Uptime. The Flux version badge can't use a `flux_instance_info` query
-- that metric is only emitted by
[fluxcd/flux-operator](https://github.com/fluxcd/flux-operator), and this repo runs
classic self-managed Flux (`flux bootstrap github`), which doesn't run that operator.
Instead it's derived from kube-state-metrics' `kube_pod_container_info`, matching the
`source-controller` pod's image tag (`ghcr.io/fluxcd/source-controller:v1.9.4@sha256:...`)
via `label_replace` -- every Flux GOTK controller container is named `manager` (verified
against `kubernetes/flux/cluster/flux-system/gotk-components.yaml`), so this generalizes
to any of them. CPU/memory usage badges also avoid `instance:node_cpu_utilisation:rate5m`-style
recording rules (a common kube-prometheus-stack pattern, but bundled rules whose exact
names could drift across chart versions) in favor of the underlying raw node-exporter
metrics directly.

Exposed via HTTPRoute on the `external` Gateway only (`kromgo.alexandremathieu.com`) --
GitHub has to fetch the badge images from the public internet to render them in the
README, so it can't sit behind the internal-only Gateway.

## Consequences

Adds a second real workload to the 8GB-per-node budget alongside Gatus, sized as small
as the badges allow but not free. No alerting or dashboards come with this -- it is
metrics-for-badges only; a real observability stack (Grafana, Alertmanager, log
aggregation) is still the open decision the original ADR left on the table. Prometheus
data doesn't survive a pod restart (by design, see above) -- fine for instant-value
badges, not fine if this ever needs to answer "what happened at 3am last night."
