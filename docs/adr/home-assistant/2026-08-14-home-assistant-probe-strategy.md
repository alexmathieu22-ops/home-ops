# Lenient liveness/startup, strict readiness only, `/` instead of `/healthz`

Date: 2026-08-14

## Status

Accepted

## Context

Matches onedr0p's actual pattern (not buroa's, which shares the strict health check
across liveness AND readiness). `/healthz` (what both references actually use) is NOT a
native HA Core endpoint — confirmed via curl (404) and research: it only exists if a
third-party custom component (hass-simple-healthcheck) is installed, which neither
reference's HelmRelease shows adding, so their setups must already have it from prior
config. A fresh install has no custom components, so it 404s forever.

## Decision

Liveness/startup are plain (no custom/type), which app-template renders as a bare TCP
check against the primary port, lenient, never killing the container just for still
booting. Only readiness runs a strict check; failing it just withholds traffic, it
doesn't restart anything. Using `/` instead of `/healthz`: Kubernetes' built-in HTTP
probe treats any 2xx-3xx as success, and `/` reliably returns 302 (onboarding redirect)
on a stock install — confirmed working via curl.

## Consequences

A fresh install works out of the box without needing hass-simple-healthcheck installed
first. This is fine given the lenient liveness/startup probes (see
[home-assistant-extended-timeout](2026-08-14-home-assistant-extended-timeout.md) for the related timeout headroom): a slow
boot or venv rebuild withholds traffic via readiness rather than triggering a restart.
