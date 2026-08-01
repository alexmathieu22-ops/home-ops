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
