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

- [ ] A GitHub App created at <https://github.com/settings/apps/new>, webhook disabled,
      with repository permissions: Contents (R&W), Pull requests (R&W), Issues (R&W),
      Checks (R&W), Commit statuses (R&W), Workflows (R&W), Metadata (Read) — installed
      only on this repo
- [ ] Its Client ID and a generated private key, stored in the `home-ops` 1Password
      vault as an item named `github-bot` (fields `GITHUB_BOT_APP_CLIENT_ID` and
      `GITHUB_BOT_APP_PRIVATE_KEY`)
- [ ] A **separate** 1Password Service Account, scoped read-only to that one item (don't
      reuse the cluster's ESO service account from
      [secret-zero](secret-zero.md) — keep CI's blast radius independent of the
      cluster's)
- [ ] That service account's token stored as the `OP_SERVICE_ACCOUNT_TOKEN` repo secret
      (`gh secret set OP_SERVICE_ACCOUNT_TOKEN`)
- [ ] Branch protection on `main` requiring the `Validate Kubernetes manifests` and
      `Validate talhelper config` checks, and "Allow auto-merge" enabled on the repo —
      without a required check, automerge has nothing to gate on

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

Everything else — new majors, most app version bumps, anything not matched above —
opens as a normal PR for manual review and merge.

## Labels

`.github/labels.yaml` declares `type/major|minor|patch|digest`, synced by
[`.github/workflows/label-sync.yaml`](../../.github/workflows/label-sync.yaml) on every
push to `main` that touches that file (and nightly). Renovate's `labels.json5` rules
apply these based on update type so the PR list is scannable at a glance.
