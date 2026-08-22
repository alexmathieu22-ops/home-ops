# 0008. Mute permanent Rook-Ceph health warnings; rotate daemon keys for CVE-2025-30156

## Status

Accepted

## Context

`TOO_FEW_OSDS` and `POOL_NO_REDUNDANCY` are permanent given the single-OSD topology (see
[0006](0006-rook-ceph-topology-and-local-path-interim.md)), not transient noise. The
`AUTH_INSECURE_*` trio is a separate, harder constraint: CSI/client keys must stay on
`aes` — `aes256k` needs kernel 7.0+, nodes are on an older kernel, and no current Talos
release ships that kernel yet.

## Decision

Muting (not fixing) `TOO_FEW_OSDS`/`POOL_NO_REDUNDANCY` is what makes `HEALTH_OK`
achievable for tuppr's health checks. Unmute both once a 2nd/3rd OSD host exists and
`replicated.size` is bumped back up. The `AUTH_INSECURE_*` mutes are a hard blocker, not
caution — unmute once a Talos release ships kernel 7.0+. Daemon (mon/mgr/osd) keys,
separately, are already rotated to `aes256k`
(`security.cephx.daemon.keyRotationPolicy: KeyGeneration`) as a one-off fix for
CVE-2025-30156 (weak integrity check on aes cephx service tickets) — Ceph/Rook were
already on CVE-fixed versions, only the keys hadn't rotated yet.

## Consequences

`HEALTH_OK` on this cluster does not mean "fully redundant" — it means "healthy given a
topology that's muted for known, tracked reasons." Anyone debugging Ceph health should
check this ADR (and [0006](0006-rook-ceph-topology-and-local-path-interim.md)) before
treating a muted warning as newly-relevant. `AUTH_INSECURE_CLIENT_KEY_TYPE` /
`AUTH_INSECURE_KEYS_ALLOWED` / `AUTH_INSECURE_KEYS_CREATABLE` stay muted until Talos
ships a kernel new enough for `aes256k` client keys — daemon keys are unaffected by that
constraint and are already on `aes256k`.
