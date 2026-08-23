# Use ESO's 1Password SDK provider for secrets

Date: 2026-08-01

## Status

Accepted

## Context

External Secrets Operator supports multiple ways to reach 1Password: the newer
`onepasswordSDK` provider, the older Connect-based `onepassword` provider, a self-hosted
1Password Connect server, or Vaultwarden. The tradeoffs among these are recorded in
docs/planning/PROJECT_BRIEF.md's decision table.

## Decision

`ClusterSecretStore` uses ESO's `onepasswordSDK` provider. Its `remoteRef.key` format is
`<item>/[section/]<field>`, with no separate `property` field — different from other ESO
providers.

## Consequences

Double check the exact field shape against the installed ESO chart's CRD if
reconciliation fails; this provider surface is newer than a given knowledge cutoff can
fully guarantee.
