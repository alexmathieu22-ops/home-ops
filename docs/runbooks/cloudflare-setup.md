# Runbook: Cloudflare setup

Cloudflare is used for two independent things in this repo — neither is required for
Headscale/VPN access, which works with zero Cloudflare setup:

1. **cert-manager's DNS-01 solver** — proves domain ownership to get a real Let's Encrypt
   cert for the internal-only Gateway (`*.internal.<domain>`, VPN-reachable only). Optional:
   without it, internal apps are just plain HTTP or self-signed HTTPS.
2. **cloudflared (Cloudflare Tunnel)** — the only thing needed for actually exposing an app
   publicly, no port-forward or public IP required.

## Prerequisites

- [x] Domain on Cloudflare. If it was **registered through Cloudflare Registrar directly**
      (as opposed to registered elsewhere and pointed at Cloudflare), the zone is already
      active — there's no separate "add site" / nameserver step. Confirm by logging into
      [dash.cloudflare.com](https://dash.cloudflare.com); the domain should just be listed
      on the account landing page.
- [x] 1Password vault/Service Account set up (`docs/runbooks/secret-zero.md`)

## 1. API token for cert-manager

Dashboard → your profile icon (top right) → **My Profile** → **API Tokens** → **Create
Token** → **"Edit zone DNS"** template → scope to the **specific zone** (not "All zones") →
create, copy the token (shown once).

Store it in 1Password — item `cloudflare-api-token`, field `credential`:

```bash
op item create --category=password --vault=home-ops --title=cloudflare-api-token credential="<paste-token>"
```

(Or via the 1Password GUI: new item → **+ add field** → type Password/Text → click the
field's *label* to rename it to `credential` → paste the value into it.)

## 2. Cloudflare Tunnel for cloudflared

```bash
brew install cloudflared
cloudflared tunnel login       # opens a browser to authorize
cloudflared tunnel create home-ops
```

**Getting the token — this is the step most likely to trip you up.** There are three
different things Cloudflare/`cloudflared` can hand you here, and only one is correct:

| What you might grab | Looks like | Correct? |
| --- | --- | --- |
| Tunnel ID (UUID) — from the dashboard's tunnel list, or the `TunnelID` field in the credentials JSON | `4dab5d47-2d5b-42ee-a...` (36 chars) | ❌ No |
| `TunnelSecret` field alone — from the credentials file `cloudflared tunnel create` writes to `~/.cloudflared/<uuid>.json` | a ~44-char base64 string | ❌ No — that's for the separate credentials-file auth mode, not what this Deployment uses |
| The actual **connector token** | a single ~150-200+ char base64 blob | ✅ Yes |

Get the real one with the CLI (works for any tunnel created since `cloudflared` 2022.3.0),
piped straight to your clipboard so there's no manual copy-paste to get wrong:

```bash
cloudflared tunnel token home-ops | pbcopy
cloudflared tunnel token home-ops | wc -c   # sanity check — should be 150+, not 36 or 44
```

Store it in 1Password — item `cloudflared-tunnel-token`, field `credential` — same pattern
as above, pasting the clipboard content as the field value.

## 3. Verify

```bash
kubectl get externalsecret -n cert-manager cloudflare-api-token
kubectl get externalsecret -n networking cloudflared-tunnel-token
kubectl get pods -n networking -l app=cloudflared
kubectl logs -n networking -l app=cloudflared --tail=20   # look for "Environment is healthy"
```

If you update a 1Password item after the `ExternalSecret` already exists, ESO's
`refreshInterval` (1h) means it won't notice right away — force it:

```bash
kubectl annotate externalsecret -n <namespace> <name> force-sync=$(date +%s) --overwrite
kubectl rollout restart deployment -n networking cloudflared   # if it's cloudflared specifically
```

## 4. Public hostname routing (once an app actually exists)

Zero Trust dashboard → **Networks** → **Tunnels** → `home-ops` → **Public Hostname** tab →
add an entry mapping `whatever.yourdomain.com` → the internal Kubernetes Service (e.g.
`http://immich.default.svc.cluster.local:2283`). This is what "routes by hostname, not DNS
records pointing at an IP" means — no `config.yml`/ingress ConfigMap needed in this repo.
Nothing to do here until an app is deployed.
