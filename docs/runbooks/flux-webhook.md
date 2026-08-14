# Runbook: Flux GitHub webhook (push-to-reconcile)

Matches onedr0p/home-ops and buroa/k8s-gitops: a `Receiver` (notification-controller) lets
GitHub tell Flux about a push immediately, instead of Flux finding out on its next
`GitRepository` poll (`interval: 1m0s` today — usually not the bottleneck, but this removes
even that wait). Manifests already committed:
`kubernetes/apps/flux-system/webhooks/app/` (`Receiver`, `ExternalSecret`, `HTTPRoute`).

Requires the [cloudflared tunnel](cloudflare-setup.md) to be live — GitHub's servers need
to reach the cluster over the public internet, and this repo has no other public ingress
path.

## 1. Generate the shared secret

GitHub signs each delivery with HMAC-SHA256 using this as the key; source-controller
validates it the same way. Any high-entropy string works:

```bash
openssl rand -hex 20
```

Store it in 1Password — item `flux-webhook-token`, field `credential` (same pattern as
`cloudflare-api-token`, see [secret-zero.md](secret-zero.md)):

```bash
op item create --category=password --vault=home-ops --title=flux-webhook-token credential="<paste-generated-value>"
```

## 2. One-time public hostname (only if not already done)

`flux-webhook.alexandremathieu.com` rides the same wildcard tunnel route as every other
public app — see [cloudflare-setup.md](cloudflare-setup.md)'s "Public hostname routing"
step. If that `*.alexandremathieu.com` entry already exists, there's nothing to add here.

## 3. Get the actual webhook path

The path segment is `sha256(token+name+namespace)`, not guessable ahead of time — read it
from the `Receiver`'s status once it's reconciled:

```bash
kubectl get receiver -n flux-system github-flux-system -o jsonpath='{.status.webhookPath}'
```

Full webhook URL is `https://flux-webhook.alexandremathieu.com` + that path.

## 4. Add the webhook on GitHub

Repo → **Settings** → **Webhooks** → **Add webhook**:

- Payload URL: the URL from step 3
- Content type: `application/json`
- Secret: the same value stored in 1Password in step 1
- Events: just the **push** event (matches the `Receiver`'s `spec.events`)

GitHub will send a ping on save — check it succeeded under the webhook's **Recent
Deliveries** tab (green check).

## 5. Verify

```bash
kubectl get externalsecret -n flux-system flux-webhook-token
kubectl get receiver -n flux-system github-flux-system
kubectl logs -n flux-system -l app=source-controller --tail=20   # look for a POST /hook/... after a real push
```

Push a trivial commit and confirm `flux get sources git flux-system` picks up the new
revision within a few seconds, well under the 1-minute poll interval.
