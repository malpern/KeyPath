# installBundledKanata False Success: Stale Registration + Throttle Interaction

**Date:** 2026-02-28  
**Severity:** User-facing reliability bug (false green, then service stopped/no TCP)  
**Status:** Fixed (hotfix), hardening follow-up planned

## Symptom

After installer actions reached green, users still saw:

- "no tcp" warnings
- "Kanata service stopped" shortly after success

In affected runs, install/repair actions could report success before Kanata was actually runtime-ready.

## Incident Timeline (Representative)

1. `installBundledKanata` starts and replaces the system Kanata binary.
2. Service state appears SMAppService-enabled but launchd cannot load it (stale registration).
3. Generic install throttle suppresses recovery in some sequences.
4. Restart-window heuristics temporarily allow healthy-ish interpretation.
5. Action reports success/green.
6. Seconds later: launchctl reports not-found / TCP probe fails / UI shows stopped.

## Root Cause Chain

1. **Postcondition gap**
   - `installBundledKanata` did not require bounded verification of `running + TCP responding` before returning success.

2. **Throttle/stale interaction**
   - Stale `.enabled but not loaded` recovery could be skipped because normal install-attempt throttle was applied too early.

3. **Health semantics drift**
   - Registration (`SMAppService.status == .enabled`) and restart windows could be over-weighted relative to runtime evidence.

4. **Transient false-positive risk**
   - `launchctl` not-found + no process + no TCP could still pass through transient pathways in some flows.

## Fixes Landed (Hotfix)

1. `installBundledKanata` now performs strict bounded readiness verification after binary replacement and service install refresh.
2. Stale SMAppService recovery bypasses generic install throttle.
3. Startup/restart heuristics no longer produce success without runtime readiness.
4. Health checks for installer single-action recipes (`installBundledKanata`, `replaceKanataWithBundled`) now require strict Kanata readiness.
5. Service health logic treats stale enabled-not-loaded as not loaded and unhealthy.

## Verification Checklist

- [x] Stale + throttle scenario: stale recovery executes even within throttle window.
- [x] Persistent launchctl 113 + no runtime + no TCP yields installer failure (not success).
- [x] `installBundledKanata` times out/fails when readiness is not achieved.
- [x] Delayed readiness succeeds once both process and TCP are true.
- [x] Main startup gate waits for TCP responsiveness before reporting ready.
- [ ] 48h post-release log monitoring window completed.

## Follow-up

- Phase 2 hardening: continue extracting pure decision functions and unify readiness usage across installer and runtime gate paths.
