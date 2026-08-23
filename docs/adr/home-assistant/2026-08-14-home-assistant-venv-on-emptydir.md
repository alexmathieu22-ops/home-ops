# Keep Home Assistant's `.venv` on scratch/`emptyDir`, not the persistent PVC

Date: 2026-08-14

## Status

Accepted

## Context

Tried moving `.venv` onto the persistent config PVC to avoid rebuilding it on every
restart, but local-path's PVC directory isn't chowned to uid 1000 the way `emptyDir` is
("Permission denied" writing `.venv/CACHEDIR.TAG`), unlike `emptyDir` which gets correct
`fsGroup` ownership automatically.

## Decision

Reverted rather than fight local-path's permission model — matches buroa's actual
pattern. This is fine now that liveness/startup are lenient (see
[home-assistant-probe-strategy](2026-08-14-home-assistant-probe-strategy.md)): a restart means a slow venv rebuild, not
a crash loop.

## Consequences

Every pod restart rebuilds the Python venv from scratch, which is why the extended
HelmRelease timeout ([home-assistant-extended-timeout](2026-08-14-home-assistant-extended-timeout.md)) and lenient
liveness/startup probes ([home-assistant-probe-strategy](2026-08-14-home-assistant-probe-strategy.md)) both matter here.
Revisit if local-path's permission model changes, or once storage moves to `ceph-block`.
