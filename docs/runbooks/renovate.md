# Runbook: Renovate

Dependency updates run as a **self-hosted** Renovate job in
[`.github/workflows/renovate.yaml`](../../.github/workflows/renovate.yaml) — not the hosted
Mend/Renovate GitHub App. That choice is deliberate, not cosmetic: it's the only way
automerge actually works end to end.

## Why self-hosted

If Renovate opened PRs using the workflow's default `GITHUB_TOKEN`, GitHub's own
recursion guard kicks in — events produced by `GITHUB_TOKEN` don't trigger other
workflow runs. That means [`ci.yaml`](../../.github/workflows/ci.yaml) (kubeconform +
talhelper validation) would never run against a Renovate PR, no status check would ever
appear, and branch protection would block the merge forever. The hosted app avoids this
because it isn't `GITHUB_TOKEN` at all — but self-hosting was still preferred here to
keep the bot scoped to exactly this repo and to keep private-registry credentials (via
Renovate `hostRules`) out of a third-party service.

The fix is a dedicated identity: a GitHub App ("bot") installed only on this repo. Its
token is a normal external actor as far as GitHub is concerned, so PRs it opens trigger
`ci.yaml` like any human's would, and `automerge` can wait on those checks and merge once
they're green.

## Prerequisites

All of these are one-time setup, already done for this repo — kept here so the same
sequence is reproducible if the bot's credentials ever need rotating or this pattern gets
reused on another repo.

### 1. Register the GitHub App

```bash
./scripts/register-renovate-github-app.sh
```

Registers the app via GitHub's
[manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)
(pre-filled permissions: Contents/Pull requests/Issues/Checks/Commit statuses/Workflows
write, Metadata read; webhook disabled) and writes the resulting Client ID + private key
straight into the `home-ops` 1Password vault as an item named `github-bot`
(`GITHUB_BOT_APP_CLIENT_ID` / `GITHUB_BOT_APP_PRIVATE_KEY`) — neither value is ever
printed to the terminal. It refuses to run if `op` is authenticated as a service account
(read-only, can't write the item) instead of a personal account.

The one step it can't automate away: GitHub requires you to personally review and click
"Create GitHub App" in your own logged-in browser, so the script opens that page and
waits for the redirect back. It prints the app's install URL last — installing it on this
repo is a separate manual click the manifest flow doesn't cover.

If it fails after the app is already created on GitHub's side (e.g. the 1Password write
fails), don't re-run the script — it'll try to create a second app with the same name.
Instead generate a new private key from the app's own settings page
(`https://github.com/settings/apps/<slug>` → Private keys → "Generate a private key") and
store it by hand:

```bash
op item create --vault home-ops --category "API Credential" --title github-bot \
  "GITHUB_BOT_APP_CLIENT_ID[text]=<client id from the app's General page>" \
  "GITHUB_BOT_APP_PRIVATE_KEY[text]=$(cat ~/Downloads/<slug>.*.private-key.pem)"
```

### 2. A separate, CI-scoped 1Password service account

Don't reuse the cluster's ESO service account from [secret-zero](secret-zero.md) — keep
CI's blast radius independent of the cluster's. `op service-account create` scopes at the
vault level only (no per-item granularity), so this grants read-only access to everything
in `home-ops`, not just `github-bot` — still a separate, independently-revocable,
read-only credential from ESO's. For tighter isolation, move `github-bot` into its own
vault first and scope to that instead.

```bash
unset OP_SERVICE_ACCOUNT_TOKEN   # make sure this runs under your personal account
eval $(op signin)

op service-account create renovate-ci --vault home-ops:read_items --raw \
  | gh secret set OP_SERVICE_ACCOUNT_TOKEN --repo alexmathieu22/home-ops
```

The token is piped directly into the GitHub secret and never displayed.

### 3. Repo settings so automerge has something to gate on

```bash
gh api repos/alexmathieu22/home-ops --method PATCH -f allow_auto_merge=true

gh api repos/alexmathieu22/home-ops/branches/main/protection \
  --method PUT \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Validate Kubernetes manifests", "Validate talhelper config"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

No required reviews (solo repo) — just the two CI jobs from `ci.yaml`. Without a required
check, `automerge: true` has nothing to wait on.

## Config layout

```
.renovaterc.json5          # entrypoint: shared preset + timezone + local extends
.renovate/
├── automerge.json5         # what's allowed to merge itself, and under what conditions
├── grouping.json5          # dependencies bumped together as one PR
└── labels.json5            # type/major|minor|patch|digest labelling
```

`.renovaterc.json5` itself only lists `extends` — the actual `packageRules` live in
`.renovate/*.json5`, pulled back in via self-referencing local presets
(`github>alexmathieu22/home-ops//.renovate/automerge.json5`, etc.). Renovate resolves
these against the repo on GitHub at runtime, merging each file's `packageRules` array
into the final config — so a change to any `.renovate/*.json5` file only takes effect
once it's on `main` (this is also why the Renovate workflow's `paths:` trigger watches
`.renovate/**.json5` alongside the entrypoint). This split is the same pattern
[buroa/k8s-gitops](https://github.com/buroa/k8s-gitops) uses (`.renovate/autoMerge.json5`,
`groups.json5`, `labels.json5`); naming here differs slightly but the mechanism is
identical.

The bulk of the actual behavior — semantic commit messages, the dependency dashboard,
GitHub Actions digest-pinning, `.yaml`/`.yaml.j2` manager coverage — comes from the
shared [`home-operations/renovate-presets`](https://github.com/home-operations/renovate-presets)
base that both [onedr0p/home-ops](https://github.com/onedr0p/home-ops) and
buroa's repos extend too. This repo's own `packageRules` are intentionally a subset of
theirs — only the rules for dependencies actually present in this cluster (`rook-ceph`
grouping, `home-operations/*` image digests) — not a full copy of every group/automerge
rule from a bigger cluster.

## Automerge rules, in order of how much trust they extend

| Rule | Waits for CI? | Cooldown |
|---|---|---|
| `home-operations/*` image digest bumps | yes | none |
| Renovate config preset bumps | no | none |
| `actions/*`, `renovatebot/*` GitHub Actions | no | 1 minute |
| Any other GitHub Actions minor/patch/digest | no | 3 days |
| Container image / Helm chart minor or patch bumps, except the exclusions below | yes | 3 days |

The last rule is broad by design — it's the "almost all minors" default for app
dependencies — but it excludes anything whose blast radius reaches beyond a single app:
Talos node versions, Kubernetes control-plane versions (both driven by
[tuppr](../../kubernetes/apps/system-upgrade/tuppr)), Cilium (CNI), Rook-Ceph (the only
storage layer), Flux's own controllers (`gotk-components.yaml` — the thing that applies
every other fix), and the two ingress paths into the cluster (Envoy Gateway,
cloudflared). Those stay on major-bump behavior: manual PR, manual review, manual merge,
regardless of update type. CI here is schema validation only (kubeconform + talhelper) —
it catches malformed manifests, not runtime regressions, which is part of why the
critical-path exclusions above don't rely on CI green as sufficient trust.

Everything else not matched by any rule above — new majors on non-excluded deps, and any
dependency type outside `docker`/`helm` — opens as a normal PR for manual review and
merge.

## Labels

`.github/labels.yaml` declares `type/major|minor|patch|digest`, synced by
[`.github/workflows/label-sync.yaml`](../../.github/workflows/label-sync.yaml) on every
push to `main` that touches that file (and nightly). Renovate's `labels.json5` rules
apply these based on update type so the PR list is scannable at a glance.
