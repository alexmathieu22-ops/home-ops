# Runbook: secret zero

This repo uses zero SOPS. Every secret except one flows through
`ExternalSecret -> 1Password` once External Secrets Operator (ESO) is running. The one
exception is the credential ESO itself needs to talk to 1Password in the first place —
the 1Password Service Account token. That's "secret zero," and it's pushed into the
cluster by a one-time OpenTofu apply from your authenticated local `op` CLI session. It
is never committed to Git and never SOPS-encrypted.

## Prerequisites (deferred — not done yet, per PROJECT_BRIEF.md)

- [ ] 1Password account
- [ ] A dedicated vault for infra secrets (separate from your personal vault)
- [ ] A 1Password **Service Account**, scoped only to that infra vault
- [ ] `op` CLI installed and signed in locally (no asdf plugin for it — install separately)

Until these exist, `terraform/bootstrap` is fully scaffolded but `tofu apply` will fail
fast with a clear validation error rather than silently doing nothing — see
[`terraform/bootstrap/variables.tf`](../../terraform/bootstrap/variables.tf).

## Running it (once the above exists)

```bash
export TF_VAR_onepassword_service_account_token=$(op read "op://infra/eso-service-account/token")
tofu -chdir=terraform/bootstrap init
tofu -chdir=terraform/bootstrap apply
```

This creates:

- the `external-secrets` namespace
- a `onepassword-service-account-token` Secret in that namespace, which ESO's
  `ClusterSecretStore` (in `kubernetes/infrastructure/external-secrets`) references to
  authenticate its 1Password SDK provider

Run this once per cluster lifetime — again only if you rotate the Service Account token.
Every other secret in every app is provisioned by an `ExternalSecret` resource pulling
from 1Password; never hand-create a Kubernetes Secret for app credentials.

## Why OpenTofu, not `op inject` + `kubectl apply`

Reference repos in this space (e.g. [onedr0p/home-ops](https://github.com/onedr0p/home-ops),
[buroa/k8s-gitops](https://github.com/buroa/k8s-gitops)) skip Terraform/OpenTofu entirely
for this step: a plain `Secret` manifest with `stringData.token: op://vault/item/field`,
applied via `kustomize build | op inject | kubectl apply -f -`. No state file, no
provider — `op inject` just substitutes the reference inline. That's a genuinely simpler
option for a single Secret and was considered here.

This repo keeps OpenTofu because PROJECT_BRIEF.md locked it in deliberately and it was
already implemented and working by the time the alternative got evaluated — not because
OpenTofu is uniquely correct for this job. If you're starting fresh or find the state
file (`terraform/bootstrap/.terraform`, gitignored) annoying to manage, the `op inject`
approach is a reasonable swap: drop `terraform/bootstrap/`, add a `bootstrap/` directory
with a kustomize-rendered `Secret` + `op inject`, and call it from
`docs/runbooks/cluster-bootstrap.md` instead of `tofu apply`.

Similarly, `flux bootstrap github` (this repo) is the imperative one-time CLI path for
installing Flux itself. Those same reference repos instead install
[flux-operator](https://github.com/controlplaneio-fluxcd/flux-operator) + a `FluxInstance`
CR via Helm, making Flux's own install declarative and Renovate-bumpable, and stage
Cilium/cert-manager/external-secrets via `helmfile` (with CRDs pre-seeded cluster-wide
*before* Flux reconciles anything — a cleaner fix for the CRD/CR-ordering races this repo
instead solves with per-component `app/`+`config/` Kustomization splits, see
`kubernetes/infrastructure/*/ks.yaml`). Same tradeoff: more correct/declarative, more
tooling (`helmfile`, `just`) and a bigger rework of an already-working bootstrap. Worth
revisiting if the CRD-race workarounds start feeling like a tax.
