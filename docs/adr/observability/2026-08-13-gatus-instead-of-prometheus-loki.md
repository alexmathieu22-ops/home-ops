# Run Gatus instead of kube-prometheus-stack + Loki

Date: 2026-08-13

## Status

Accepted

## Context

kube-prometheus-stack + Loki + Alloy (what onedr0p/buroa actually run) targets
multi-node clusters with real RAM headroom; on this single 8GB node it competed with
Cilium/cert-manager/external-secrets/apps for the same tight budget.

## Decision

Gatus alone covers "is everything up" without that cost. Whether to add real
metrics/logs later (self-hosted once node 2 exists, or Grafana Cloud's free tier) is an
open decision, not made here. No persistence yet: uptime history resets on pod restart,
acceptable for an "is it up right now" status page. Flip on once storage is viable.

Deployed via bjw-s's `app-template` (matching local-path-provisioner), adapted from
buroa/k8s-gitops's Gatus setup rather than the `twin` chart used before -- comparison
requested and confirmed against buroa's actual file. The interesting piece is
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

## Consequences

Uptime history resets on every pod restart until persistence is enabled. There is no
real metrics/log backend yet -- that remains an open decision. The public `external`
Gatus status page currently also exposes internal-only app names via `--gateway-name
internal`; narrow that if that becomes undesirable.
