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
- [ ] `tofu` installed (`asdf install` picks up the pinned version in `.tool-versions`)

The VM, its networking/firewall rules, and the DNS record are provisioned with the
OpenTofu config in [`terraform/headscale/`](../../terraform/headscale) rather than by
hand — this is the one place in the repo where Terraform/OpenTofu earns its keep (real
cloud resources with real lifecycle, per the reasoning in `docs/runbooks/secret-zero.md`'s
"Why not OpenTofu" section, which explicitly carves out this VM as the exception). It also
bakes in a cloud-init script that installs and configures Headscale + Caddy on first boot,
so there's no manual SSH setup step at all.

## 1. OCI API credentials

OpenTofu needs its own API key, separate from your Console login.

Console → profile icon (top right) → **My profile** → **API keys** → **Add API key** →
**Generate API key pair** → download the private key → **Add**. Save the downloaded key
somewhere durable (e.g. `~/.oci/headscale-terraform.pem`) — it's never committed, and
Oracle doesn't let you re-download it. The confirmation dialog shows a config snippet with
your `user`, `fingerprint`, and `tenancy` OCIDs — copy those for the next step.

## 2. Configure variables

```bash
cd terraform/headscale
cp terraform.tfvars.example terraform.tfvars
```

Fill in `terraform.tfvars` (gitignored) using:

- `oci_tenancy_ocid`, `oci_user_ocid`, `oci_fingerprint`, `oci_private_key_path` — from
  step 1
- `oci_region`, `oci_compartment_ocid` — region shown in the Console's top-right region
  selector; the compartment OCID can be the tenancy OCID itself for a single-VM personal
  setup (root compartment)
- `ssh_public_key` — your public key, e.g. `cat ~/.ssh/id_ed25519.pub`
- `cloudflare_api_token`, `cloudflare_zone_id` — reuse the same scoped API token from
  `docs/runbooks/cloudflare-setup.md` step 1 (or mint a second one with identical "Edit
  zone DNS" permissions); zone ID is on the domain's Cloudflare dashboard overview page

## 3. Apply

```bash
tofu init
tofu plan   # review: 1 VCN, 1 subnet, 1 security list, 1 instance, 1 DNS record
tofu apply
```

Always-Free Ampere capacity is genuinely scarce in some regions and fluctuates by the
minute — `Out of host capacity` on the instance is expected, not a config error (the
networking resources above it will have applied fine; re-running only retries the
instance). Either retry `tofu apply` by hand every so often, or let it retry for you:

```bash
bash retry-apply.sh          # retries every 60s until it succeeds
bash retry-apply.sh 30       # or pass a custom interval in seconds
```

If it's still failing after a long while, try a different `availability_domain_index` in
`terraform.tfvars` (a region has 1-3 ADs; not all may have free Ampere capacity at a given
moment) — though single-AD regions like `ca-montreal-1` don't have that option, so a
different region may be the only lever left.

**Current state**: `ca-montreal-1` hit zero Ampere A1 capacity across 500+ retries, so
`instance.tf` is temporarily on `VM.Standard.E2.1.Micro` instead (a separate, uncontended
Always-Free x86 allowance — 1/8 OCPU / 1GB RAM, fixed, no `shape_config`). It's tight for
Headscale + Caddy under real load; switch back to `VM.Standard.A1.Flex` (see git history
for the exact block) once Ampere capacity frees up.

Cloud-init takes a minute or two after the VM boots to install Headscale, install Caddy,
write both configs, and start both services — `tofu apply` returns before that finishes.
Confirm it's done:

```bash
ssh ubuntu@$(tofu output -raw public_ip) 'systemctl is-active headscale caddy'
```

Caddy requests and renews its Let's Encrypt cert automatically on first HTTPS request — no
separate certbot step, and no manual config editing: `server_url`, the embedded DERP
relay, and `dns.base_domain: internal.alexandremathieu.com` are all set by the cloud-init
template in `terraform/headscale/cloud-init.yaml.tftpl`. That `base_domain` gives tailnet
devices short names (`<device>.internal.alexandremathieu.com`) resolved over MagicDNS —
separate from, and not requiring, the in-cluster Envoy Gateway's own use of that same
`*.internal.alexandremathieu.com` zone (they don't overlap in practice since one resolves
device names and the other resolves app hostnames).

## 4. Create a pre-auth key

Cloud-init already ran `headscale users create home-ops` on first boot. SSH in and mint
the key -- newer Headscale CLI versions want the user's numeric ID, not the username, for
`--user` (check it with `headscale users list` if it's not `1`):

```bash
ssh ubuntu@$(tofu output -raw public_ip)
sudo headscale preauthkeys create --user 1 --reusable --expiration 8760h
```

`--reusable` because the same key authenticates both the in-cluster subnet router and any
personal devices you add later; `8760h` (1 year) avoids re-minting it constantly — rotate
it the same way if it ever needs invalidating (`headscale preauthkeys expire`).

Copy the printed key (a single `hskey-auth-...` string).

## 5. Store the key in 1Password

Matches the format the cluster's `ExternalSecret` already expects
(`kubernetes/apps/networking/headscale-subnet-router/app/externalsecret.yaml`, key
`headscale-subnet-router-authkey/credential`):

```bash
op item create --category=password --vault=home-ops \
  --title=headscale-subnet-router-authkey credential="<paste-preauth-key>"
```

(Or via the 1Password GUI, same pattern as `docs/runbooks/cloudflare-setup.md` step 1: new
item → add field → rename its label to `credential` → paste the value.)

## 6. Verify the subnet router picks it up

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

## 7. Update the advertised route and approve it

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

## 8. Add personal devices to the tailnet

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

- **Oracle's stock image pre-blocks non-SSH ports**: the base Ubuntu image ships
  `iptables` rules (only `tcp/22` accepted, everything else `REJECT`ed) that sit ahead of
  `ufw`'s own chains, so `ufw allow 443/tcp` etc. silently has no effect until those are
  cleared first. Cloud-init handles this (`iptables -F INPUT` + `-P INPUT ACCEPT` before
  the `ufw` rules), but if a VM behaves like this — SSH works, 80/443 give `Connection
  refused` from outside despite `ufw status` showing them allowed — check
  `sudo iptables -L INPUT -n --line-numbers` for a leftover `REJECT` rule.
- **State file**: `terraform/headscale/terraform.tfstate` is local and gitignored (along
  with `terraform.tfvars`) — nothing backs it up. Fine for a single-operator personal
  setup where losing it just means re-importing or recreating the VM; revisit with a
  remote backend (e.g. an OCI Object Storage bucket) if that stops being true.
- **Backups**: Headscale's actual data is `/var/lib/headscale/db.sqlite` on the VM (nodes,
  routes, pre-auth keys) — not reproducible by re-running `tofu apply`, which only manages
  the surrounding infrastructure, not that file. `cp` it somewhere durable before any risky
  change (OS upgrade, Headscale major version bump).
- **Updates**: bump `headscale_version` in `terraform.tfvars` and `tofu apply` — that only
  affects a *new* instance (cloud-init runs once, on first boot); on an existing VM, update
  the `.deb` manually the same way cloud-init installed it (`curl` + `dpkg -i`). Renovate
  doesn't track this version since it's outside the GitOps tree.
- **Why not run Headscale in-cluster instead**: considered and rejected — it would make
  the VPN path (and therefore remote cluster access) depend on the cluster's own
  availability, defeating the point of having an out-of-band way in when something's
  actually broken.
- **Why Terraform here but not for secret-zero**: this VM is real infrastructure with a
  real lifecycle (create, resize, recreate) — the case Terraform is actually built for. A
  single pre-auth key/token, by contrast, has no lifecycle beyond "exists, gets rotated
  occasionally" — see `docs/runbooks/secret-zero.md`'s "Why not OpenTofu" section for the
  full reasoning on why that stays `op inject` + `kubectl apply` instead.
