# Runbook: Headscale on Oracle Cloud

Headscale (the self-hosted Tailscale control server) runs **outside** this Kubernetes
cluster, on a small always-on VM — not as a workload in `kubernetes/apps/`. That's
deliberate: the tailnet is the front door used to reach the cluster over VPN, so it can't
depend on the cluster being up. What *does* live in the cluster is the subnet router
(`kubernetes/apps/networking/headscale-subnet-router`) — a plain Tailscale client Pod that
joins the tailnet Headscale coordinates and advertises the home LAN CIDR into it.

Oracle Cloud's "Always Free" tier is the host: a real public IPv4 address (no CGNAT,
unlike most home ISP connections) and an ARM VM with enough headroom for Headscale, for
$0/month indefinitely (not a trial).

## Prerequisites

- [x] Domain on Cloudflare (`docs/runbooks/cloudflare-setup.md`) — used here only for one
      DNS record, no Cloudflare Tunnel involved
- [x] 1Password vault/Service Account set up (`docs/runbooks/secret-zero.md`)
- [ ] An Oracle Cloud account (email + phone verification; a credit card is required to
      sign up but Always Free resources are never billed)

## 1. Create the VM

Oracle Cloud Console → **Compute** → **Instances** → **Create instance**.

- **Name**: `headscale`
- **Image**: Ubuntu 24.04 (or later LTS) — Always Free-eligible
- **Shape**: click **Change shape** → **Ampere** → `VM.Standard.A1.Flex` → 1 OCPU / 6GB RAM
  (comfortably inside the Always Free 4 OCPU / 24GB Ampere allowance)
- **Networking**: create a new VCN if you don't have one (defaults are fine) — it needs a
  public subnet with internet gateway, which the console's default VCN wizard sets up
- **Add SSH key**: paste your public key (or let the console generate one and download it —
  either works, but pasting your own means you don't have to manage a new keypair)

Create it, then note the **public IPv4 address** shown on the instance's detail page.

## 2. Open the required ports

Oracle Cloud's security lists/NSGs block everything by default, on top of the OS firewall.
Both need opening.

**VCN Security List** — instance detail page → subnet link → **Security Lists** → default
list → **Add Ingress Rules**:

| Source CIDR | Protocol | Port | Purpose |
| --- | --- | --- | --- |
| `0.0.0.0/0` | TCP | 443 | Headscale HTTPS (control server + embedded DERP) |
| `0.0.0.0/0` | TCP | 80 | Let's Encrypt HTTP-01 challenge |
| `0.0.0.0/0` | UDP | 3478 | DERP relay (STUN) |

**OS firewall** (Ubuntu ships with `iptables` rules from Oracle's image that also block
these — `ufw` is simpler to reason about):

```bash
ssh ubuntu@<vm-public-ip>
sudo apt update && sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp
sudo ufw allow 3478/udp
sudo ufw --force enable
```

## 3. DNS record

Cloudflare dashboard → your zone → **DNS** → **Add record**:

| Type | Name | Content | Proxy status |
| --- | --- | --- | --- |
| A | `headscale` | `<vm-public-ip>` | **DNS only** (grey cloud) |

Proxying (orange cloud) must be off — Headscale's clients need to reach the VM directly,
and Cloudflare's proxy doesn't forward the UDP DERP traffic anyway.

## 4. Install Headscale + Caddy

Headscale as a native binary (systemd-managed), Caddy in front of it for automatic TLS —
simpler than running Headscale's own manual cert handling.

```bash
# Headscale
HEADSCALE_VERSION=0.29.3   # check https://github.com/juanfont/headscale/releases for latest
curl -fsSL -o headscale.deb \
  "https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION}_linux_arm64.deb"
sudo dpkg -i headscale.deb
sudo systemctl enable headscale

# Caddy (official apt repo)
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | \
  sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | \
  sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy
```

Edit `/etc/headscale/config.yaml` — the relevant keys:

```yaml
server_url: https://headscale.alexandremathieu.com
listen_addr: 127.0.0.1:8080 # Caddy fronts this; not exposed directly
metrics_listen_addr: 127.0.0.1:9090

derp:
  server:
    enabled: true
    region_id: 999
    stun_listen_addr: 0.0.0.0:3478
  urls: [] # disable Tailscale's public DERP map, use only the embedded server above

database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite

dns:
  magic_dns: true
  base_domain: internal.alexandremathieu.com
```

`base_domain` gives tailnet devices short names (`<device>.internal.alexandremathieu.com`)
resolved over MagicDNS — separate from, and not requiring, the in-cluster Envoy Gateway's
own use of that same `*.internal.alexandremathieu.com` zone (they don't overlap in practice
since one resolves device names and the other resolves app hostnames).

Configure Caddy — replace `/etc/caddy/Caddyfile`:

```caddyfile
headscale.alexandremathieu.com {
    reverse_proxy 127.0.0.1:8080
}
```

```bash
sudo systemctl restart caddy
sudo systemctl start headscale
sudo systemctl status headscale caddy --no-pager
```

Caddy requests and renews the Let's Encrypt cert automatically on first request — no
separate certbot step.

## 5. Create a user and pre-auth key

```bash
sudo headscale users create home-ops
sudo headscale preauthkeys create --user home-ops --reusable --expiration 8760h
```

`--reusable` because the same key authenticates both the in-cluster subnet router and any
personal devices you add later; `8760h` (1 year) avoids re-minting it constantly — rotate
it the same way if it ever needs invalidating (`headscale preauthkeys expire`).

Copy the printed key (a single `tskey-auth-...` string).

## 6. Store the key in 1Password

Matches the format the cluster's `ExternalSecret` already expects
(`kubernetes/apps/networking/headscale-subnet-router/app/externalsecret.yaml`, key
`headscale-subnet-router-authkey/credential`):

```bash
op item create --category=password --vault=home-ops \
  --title=headscale-subnet-router-authkey credential="<paste-preauth-key>"
```

(Or via the 1Password GUI, same pattern as `docs/runbooks/cloudflare-setup.md` step 1: new
item → add field → rename its label to `credential` → paste the value.)

## 7. Verify the subnet router picks it up

The `ExternalSecret` refreshes hourly by default — force it rather than waiting:

```bash
kubectl annotate externalsecret -n networking headscale-subnet-router-authkey \
  force-sync=$(date +%s) --overwrite
kubectl rollout restart statefulset -n networking headscale-subnet-router
kubectl logs -n networking headscale-subnet-router-0 --tail=20 -f
```

Look for a line ending in `Connected` or `authenticated`, no repeated `backoff`/`retrying`.

On the Headscale VM, confirm it registered:

```bash
sudo headscale nodes list
```

## 8. Update the advertised route and approve it

`TS_ROUTES` in
[`statefulset.yaml`](../../kubernetes/apps/networking/headscale-subnet-router/app/statefulset.yaml)
is still the placeholder `192.168.1.0/24` — replace it with the real home LAN CIDR once
that's known (check the router's LAN subnet), commit, push, let Flux roll it out.

Headscale doesn't auto-approve advertised routes even from a trusted node — enable it
explicitly:

```bash
sudo headscale routes list
sudo headscale routes enable -r <route-id-from-above>
```

## 9. Add personal devices to the tailnet

Install the normal Tailscale client (App Store / Play Store / `tailscale` package), then
point it at this Headscale instance instead of Tailscale's own coordination server:

```bash
tailscale up --login-server=https://headscale.alexandremathieu.com
```

This opens a browser link for the *first* device, which Headscale ties to the `home-ops`
user; on macOS/iOS/Android use the GUI's "Use custom coordination server" login-server
field with the same URL. Once connected, `<hostname>.internal.alexandremathieu.com`
resolves any tailnet member and the advertised home LAN route is reachable through the
subnet router — including the in-cluster Envoy Gateway at
`*.internal.alexandremathieu.com` once DNS for that zone points into the cluster.

## Notes

- **Backups**: Headscale's state is just `/var/lib/headscale/db.sqlite` and
  `/etc/headscale/config.yaml` — no managed backup here yet; `cp` them somewhere durable
  before any risky change (OS upgrade, Headscale major version bump).
- **Updates**: `.deb` releases only, no apt repo — repeat the `curl`+`dpkg -i` from step 4
  with a newer version tag when needed; Renovate doesn't track this since it's outside the
  GitOps tree.
- **Why not run Headscale in-cluster instead**: considered and rejected — it would make
  the VPN path (and therefore remote cluster access) depend on the cluster's own
  availability, defeating the point of having an out-of-band way in when something's
  actually broken.
