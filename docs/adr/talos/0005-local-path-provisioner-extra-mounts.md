# 0005. Add `machine.kubelet.extraMounts` for local-path-provisioner

## Status

Accepted

## Context

Talos's root filesystem is a read-only squashfs overlay — only `/var` (the EPHEMERAL
partition) persists. local-path-provisioner's data path is repointed at
`/var/local-path-provisioner`, and the kubelet only bind-mounts a fixed set of host paths
into its own mount namespace by default. Without an explicit mount, PVCs report a healthy
StorageClass but fail to actually mount.

## Decision

`talconfig.yaml` adds an `extraMounts` patch (`source` == `destination`, both
`/var/local-path-provisioner`).

## Consequences

This is a machine config change: it must be re-applied to the real node whenever it
changes (`talhelper gencommand apply` or `talosctl apply-config`) — Flux can't push it.
See also `docs/runbooks/cluster-bootstrap.md`'s "Known limitations running single-node".
