# 0010. Extend Home Assistant's HelmRelease timeout to 10m

## Status

Accepted

## Context

First boot (venv build + HA's own init) can take longer than Flux's 5m default wait.
Helm giving up mid-boot and remediating (uninstall + retry) was compounding with the
venv-rebuild-on-restart issue (see [0012](0012-home-assistant-venv-on-emptydir.md)).

## Decision

`timeout: 10m` — real headroom instead of Helm giving up mid-boot.

## Consequences

First installs and upgrades that trigger a venv rebuild have up to 10 minutes to
complete before Helm remediates, instead of 5.
