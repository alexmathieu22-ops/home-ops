# Add a Flux GitHub webhook receiver for immediate reconcile

Date: 2026-08-13

## Status

Accepted

## Context

Without a webhook, a push only reconciles once the `GitRepository`'s 1-minute poll comes
around.

## Decision

`kubernetes/apps/flux-system/webhooks`: a notification-controller `Receiver` (type
`github`) so a push reconciles immediately — matches onedr0p/home-ops and
buroa/k8s-gitops. The `Receiver`'s `resources` list only needs the `GitRepository`, not
every downstream `Kustomization`: kustomize-controller already watches it for revision
changes, so anything sourced from it reconciles right after. Routed through the same
`external` Gateway + cloudflared tunnel as any other public app (see
[gateway-api-internal-external-split](2026-08-16-gateway-api-internal-external-split.md)) — a Service named
`webhook-receiver`, separate from notification-controller's own (see
`gotk-components.yaml`), on its dedicated `http-webhook` port. Manual GitHub-side step
(token generation, webhook creation) is `docs/runbooks/flux-webhook.md`, same shape as
`cloudflare-setup.md`'s public-hostname step.

## Consequences

Pushes reconcile immediately instead of waiting up to a minute. Setting this up requires
a manual, one-time GitHub-side step documented in `docs/runbooks/flux-webhook.md`.
