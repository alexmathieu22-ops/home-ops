# Split `ks.yaml` into two Kustomizations to avoid CRD/CR races

Date: 2026-08-02

## Status

Accepted

## Context

Several components (`cilium`, `cert-manager`, `external-secrets`, `envoy-gateway`,
`rook-ceph`) define a resource that depends on a CRD installed by that same component's
own Helm chart — e.g. cert-manager's `ClusterIssuer` needs the CRD cert-manager itself
installs. A single Kustomization applying both at once races the CRD's own registration.

## Decision

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
1Password/Cloudflare accounts exist (see docs/planning/PROJECT_BRIEF.md's "Deferred by user" list) — a
`healthCheckExprs` block checks the resource's real `Ready`/`Programmed` condition
explicitly (Gateway API's `Programmed` isn't the generic `Ready` Flux auto-detects for
most CRDs) so staying not-Ready is an accurate signal, not a false green.

## Consequences

Those specific `-config` Kustomizations (cert-manager's `ClusterIssuer`,
external-secrets' `ClusterSecretStore`, cloudflared's tunnel token) are expected to sit
not-Ready until the corresponding 1Password/Cloudflare accounts exist — that is a correct
status, not a symptom to chase.
