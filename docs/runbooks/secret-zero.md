# Runbook: secret zero

This repo uses zero SOPS. Every secret except one flows through
`ExternalSecret -> 1Password` once External Secrets Operator (ESO) is running. The one
exception is the credential ESO itself needs to talk to 1Password in the first place —
the 1Password Service Account token. That's "secret zero."

It's pushed into the cluster by rendering
[`bootstrap/kustomize/external-secrets`](../../bootstrap/kustomize/external-secrets) —
a plain `Secret` manifest whose value is a 1Password reference
(`op://infra/eso-service-account/token`) — through `op inject`, which substitutes the
real value inline, then applying the result with `kubectl`. No state file, no Terraform
provider: the Secret object in the cluster is the only source of truth, and re-running
the apply is always safe. It is never committed to Git and never SOPS-encrypted (the
committed manifest only ever contains the `op://` reference, not a real value).

## Prerequisites (deferred — not done yet, per PROJECT_BRIEF.md)

- [ ] 1Password account
- [ ] A dedicated vault named `infra` for infra secrets (separate from your personal vault)
- [ ] A 1Password **Service Account**, scoped only to that vault, with an item named
      `eso-service-account` holding the token in a field named `token`
- [ ] `op` CLI installed and signed in locally (no asdf plugin for it — install separately)

## Running it (once the above exists)

```bash
kubectl kustomize bootstrap/kustomize/external-secrets | op inject | kubectl apply --server-side -f -
```

This creates:

- the `external-secrets` namespace
- a `onepassword-service-account-token` Secret in that namespace, which ESO's
  `ClusterSecretStore` (in `kubernetes/infrastructure/external-secrets`) references to
  authenticate its 1Password SDK provider

Run this once per cluster lifetime — again only if you rotate the Service Account token.
Every other secret in every app is provisioned by an `ExternalSecret` resource pulling
from 1Password; never hand-create a Kubernetes Secret for app credentials.

## Why not OpenTofu

Evaluated on the merits (not on what was already built): the job here is pushing one
static value into the cluster as a Secret, once, touched again only on token rotation.
That doesn't exercise anything Terraform/OpenTofu is actually good at — dependency
graphs, multi-resource lifecycle, drift detection across many resources. What's left is
its cost: a state file to manage, a provider version for Renovate to track, and a second
declarative system running alongside Flux/kustomize (which is already the system of
record for every other object in this cluster) for exactly one resource.

`op inject` + `kubectl apply` does the same job with nothing extra: `op` is already
required either way (you need it to authenticate the push), the Secret in the cluster
*is* the full source of truth with no separate ledger to drift from reality, and it
reuses the same toolchain (kustomize) already used for every other manifest in this repo.
It's also the more consistent choice given this project's own stated design philosophy —
the same "fewer moving parts" reasoning behind picking Longhorn-then-Rook-Ceph over
heavier alternatives and the 1Password SDK provider over running a Connect server.

Terraform/OpenTofu would earn its keep for E2E_PLAN.md's *optional* future step of
provisioning the Oracle Cloud Headscale VM and a Cloudflare DNS zone — real cloud
resources with real lifecycle, where its value is genuine. That's the point to introduce
it, not for a single static secret today.

(Reference repos in this space, e.g. [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
and [buroa/k8s-gitops](https://github.com/buroa/k8s-gitops), use this same `op inject`
pattern. They also replace the imperative `flux bootstrap` CLI step used in this repo
with [flux-operator](https://github.com/controlplaneio-fluxcd/flux-operator) + a
`FluxInstance` CR installed via `helmfile`, making Flux's own install declarative and
Renovate-bumpable, and pre-seed CRDs cluster-wide before Flux reconciles anything — a
cleaner fix for the CRD/CR-ordering races this repo instead solves with per-component
`app/`+`config/` Kustomization splits (see `kubernetes/infrastructure/*/ks.yaml`). That
part was judged not worth the added tooling (`helmfile`, `just`) for a bootstrap step
that already works; revisit if the CRD-race workarounds start feeling like a tax.)
