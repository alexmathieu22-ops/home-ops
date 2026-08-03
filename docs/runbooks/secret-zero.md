# Runbook: secret zero

This repo uses zero SOPS. Every secret except one flows through
`ExternalSecret -> 1Password` once External Secrets Operator (ESO) is running. The one
exception is the credential ESO itself needs to talk to 1Password in the first place —
the 1Password Service Account token. That's "secret zero."

It's pushed into the cluster by rendering
[`bootstrap/kustomize/external-secrets`](../../bootstrap/kustomize/external-secrets) —
a plain `Secret` manifest whose value is a 1Password reference
(`op://home-ops/eso-service-account/token`) — through `op inject`, which substitutes the
real value inline, then applying the result with `kubectl`. No state file, no Terraform
provider: the Secret object in the cluster is the only source of truth, and re-running
the apply is always safe. It is never committed to Git and never SOPS-encrypted (the
committed manifest only ever contains the `op://` reference, not a real value).

## Prerequisites

- [x] 1Password account
- [ ] A dedicated vault named `home-ops` for infra secrets (separate from your personal vault)
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
  `ClusterSecretStore` (in `kubernetes/apps/external-secrets/external-secrets`) references to
  authenticate its 1Password SDK provider

Run this once per cluster lifetime — again only if you rotate the Service Account token.
Every other secret in every app is provisioned by an `ExternalSecret` resource pulling
from 1Password; never hand-create a Kubernetes Secret for app credentials.

`bootstrap/kustomize/components/namespace` is a reusable kustomize
[Component](https://kubectl.docs.kubernetes.io/guides/config_management/components/)
that provides the namespace generically (the consuming `kustomization.yaml`'s own
top-level `namespace:` field renames it) — matches onedr0p/home-ops and
buroa/k8s-gitops's bootstrap convention. Those repos also split `bootstrap/kustomize/`
into two top-level groups (`home-operations/`, `personal/`) because they pull secrets
from two *separate 1Password accounts*, each pushed with a different `OP_ACCOUNT` — not
just two vaults in one account. This repo uses a single account/vault, so there's just
the one `external-secrets/` group; revisit if a second, separately-scoped 1Password
account (e.g. a household/family one) ever gets added.

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

Terraform/OpenTofu does earn its keep elsewhere in this repo: `terraform/headscale`
(see `docs/runbooks/headscale-oracle-cloud.md`) provisions the Oracle Cloud Headscale VM
and its Cloudflare DNS record — real cloud resources with real lifecycle, where its value
is genuine. That's the point to introduce it, not for a single static secret like this one.

(Reference repos in this space, e.g. [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
and [buroa/k8s-gitops](https://github.com/buroa/k8s-gitops), use this same `op inject`
pattern. They also replace the imperative `flux bootstrap` CLI step used in this repo
with [flux-operator](https://github.com/controlplaneio-fluxcd/flux-operator) + a
`FluxInstance` CR installed via `helmfile`, making Flux's own install declarative and
Renovate-bumpable, and pre-seed CRDs cluster-wide before Flux reconciles anything — a
cleaner fix for the CRD/CR-ordering races this repo instead solves with per-component
`app/`+`config/` Kustomization splits (see `kubernetes/apps/*/*/ks.yaml`). That
part was judged not worth the added tooling (`helmfile`, `just`) for a bootstrap step
that already works; revisit if the CRD-race workarounds start feeling like a tax.)
