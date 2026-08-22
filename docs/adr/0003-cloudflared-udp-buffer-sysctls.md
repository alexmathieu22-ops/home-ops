# 0003. Raise UDP buffer sysctls for cloudflared's QUIC transport

## Status

Accepted

## Context

cloudflared's QUIC transport needs bigger UDP buffers than the kernel default. This was
observed directly as a warning — `wanted: 7168 kiB, got: 416 kiB` — causing periodic
reconnects.

## Decision

Set `net.core.rmem_max`/`wmem_max` sysctls in `talos/talconfig.yaml`.

## Consequences

cloudflared's QUIC connection no longer under-buffers; the periodic-reconnect symptom is
resolved by this sysctl change specifically, not by any cloudflared-side configuration.
