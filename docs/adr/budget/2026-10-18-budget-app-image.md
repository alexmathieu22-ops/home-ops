# Run the budget app from its own repo's image, behind Cloudflare Access

Date: 2026-10-18

## Status

Accepted

## Context

A small budget tracker for two people: a shared monthly plan split in proportion to
income, each person's own plan, and a running balance of who owes whom. Off-the-shelf
self-hosted options cover half of it each — Actual Budget/Firefly III do budgets but not
an income-proportional split between two people, Spliit/SplitPro do the split but not a
monthly plan. So it's written from scratch, in
[alexmathieu22/budget](https://github.com/alexmathieu22/budget) (private).

Rejected alternatives:

- **App files in this repo, mounted from a ConfigMap onto a stock python image**: no
  registry or build pipeline, but it mixes app source into the cluster repo, `server.py`
  changes need a manual `rollout restart`, and there are no versioned releases to roll
  back to.
- **Login in the app itself**: passwords, sessions and resets to maintain, when Cloudflare
  Access already gates Gatus the same way with no code.
- **Internal-only**: would put everyone who uses it on the tailnet.

## Decision

The app (stdlib-only Python + one HTML page) lives in its own repo; pushing a `vX.Y.Z`
tag there runs its tests and publishes `ghcr.io/alexmathieu22/budget:X.Y.Z`. The image is
private, so this repo pulls it with a read-only GHCR token from 1Password
(`ghcr-pull-token`, synced into a `dockerconfigjson` Secret by an ExternalSecret). This
repo only deploys that image with app-template; SQLite lives on a 1Gi `local-path` PVC.

Public at `budget.alexandremathieu.com` through the `external` Gateway, gated by a
Cloudflare Access app (`terraform/cloudflare-tunnel/access.tf`) with its own email
allow-list (`budget_allowed_emails`, separate from Gatus's). Also on the `internal`
Gateway at `budget.internal.alexandremathieu.com`, where the tailnet is the access
control and Gatus monitors it. Identity inside the app is a per-device "who are you"
choice. Each person's own expenses are hidden from the other in the UI only; the API
returns everything to anyone past Access.

## Consequences

- Shipping a change is: release in the app repo, then bump the tag (and digest) here.
- The Access app has to be applied before the HTTPRoute lands: the wildcard DNS record
  already routes `budget.<domain>` to the tunnel, so the route alone would publish the app
  with no auth.
- The origin doesn't verify Cloudflare's Access JWT; it relies on the `external` Gateway
  being reachable only from cloudflared.
- The database is on node-local storage with no backup — losing that node loses the data.
  Revisit when Rook-Ceph or a backup job exists.
