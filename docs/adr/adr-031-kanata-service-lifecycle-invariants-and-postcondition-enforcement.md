# ADR-031: Kanata Service Lifecycle Invariants and Postcondition Enforcement

## Status

Accepted

## Date

2026-02-28

## Context

A reliability incident showed a gap between installer completion signaling and actual Kanata runtime state:

1. `installBundledKanata` replaced binaries and could stop/re-register service state.
2. In stale SMAppService conditions (`.enabled` but not loaded), recovery could be skipped by generic install throttle.
3. Restart-window heuristics could briefly treat the system as healthy without process+TCP readiness.
4. The installer action could return success, then quickly degrade to "service stopped" / "no TCP".

This violated user expectations and produced false green states after install/repair flows.

## Decision

Adopt explicit service lifecycle invariants for Kanata install/repair paths:

1. **Strict postcondition for success**
   - Mutating installer actions that affect Kanata runtime must not report success until Kanata is `ready` (`running + TCP responding`) or the system is explicitly in pending Login Items approval.

2. **Stale recovery bypasses generic throttle**
   - If SMAppService is active but launchd cannot load the daemon (stale enabled registration), recovery install/register logic bypasses normal install-attempt throttling.

3. **Registration is metadata, not liveness**
   - `SMAppService.status == .enabled` is treated as registration state only.
   - Runtime health requires process and TCP evidence.

4. **Definitive unhealthy evidence is terminal for the attempt**
   - Repeated `launchctl` not-found (`exit 113`) with `!running && !responding` is not treated as transiently healthy.
   - Installer action fails with diagnostics instead of returning optimistic success.

5. **Shared terminology**
   - `registered`: SMAppService metadata
   - `loaded`: launchd discoverability
   - `running`: process present
   - `responding`: TCP probe success
   - `ready`: `running && responding`

## Consequences

### Positive

- Installer reports now match runtime reality.
- Stale-registration repair is deterministic even during throttle windows.
- "Green then stopped" transitions are reduced by fail-fast postconditions.
- Health decisions are easier to test and reason about.

### Negative

- Install/repair actions can fail more often in borderline startup conditions instead of masking failures.
- Additional polling and diagnostics add modest complexity.

### Follow-up

- Continue hardening by unifying startup-gate and installer readiness predicates and expanding integration-style regression coverage across launchctl/TCP/stale-state combinations.
