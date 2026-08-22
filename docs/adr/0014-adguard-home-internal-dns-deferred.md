# 0014. Run AdGuard Home for internal DNS resolution (deferred)

## Status

Deferred — accepted, deployed, then removed pending real router hardware (see
Consequences).

## Context

The internal Gateway's wildcard hostname (`*.internal.alexandremathieu.com`, see
[0013](0013-gateway-api-internal-external-split.md)) needs to resolve somewhere. The
ISP-provided router has no local-DNS-record capability at all (confirmed against the
vendor's own docs).

## Decision

`kubernetes/apps/networking/adguard-home` existed purely to make that wildcard hostname
resolvable. Deliberately not the house's only DNS server end-to-end: the pod's
LoadBalancer IP was set as the *primary* DHCP DNS server on the router with a public
resolver (e.g. 1.1.1.1) as *secondary* -- if the pod was ever down, general internet DNS
fell back automatically (most OS resolvers retry the secondary on timeout); only
`*.internal.alexandremathieu.com` stopped resolving. That was the deliberately accepted
blast radius for running this on a single node instead of a dedicated always-on device.

Deployed via bjw-s's `app-template`, not the gabe565 community chart previously used --
gabe565's chart is itself just a per-app wrapper around app-template's own common
library, single-maintainer, and already caused one bug (assumed web port 80, actual
default 3000). Going straight to app-template meant owning the pod spec directly (image,
ports, probes, an initContainer that copies the git-sourced config into a writable
`emptyDir`, since AdGuard needs to write back to its config file at runtime) with no
third-party packaging opinion in between -- matches onedr0p/buroa's actual convention for
apps without an official upstream chart.

## Consequences

Removed (`chore(networking): remove adguard-home, deferred pending real router
hardware`) -- deferred until a UniFi gateway replaces the ISP router, which is expected
to provide local DNS records natively and remove the need for this component entirely.
Its removal is why [0009](0009-home-assistant-loadbalancer-exposure.md) exposes Home
Assistant via a bare LoadBalancer IP instead of a Gateway route: there is currently no
working network-wide internal DNS to depend on.
