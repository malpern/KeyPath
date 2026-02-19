# False "Kanata Service Stopped" Alert

**Date:** 2026-02-19
**Severity:** User-facing false positive
**Status:** Fixed

## Symptom

KeyPath showed a "Kanata Service Stopped" alert dialog while Kanata was running normally (PID 79258, never exited, `runs = 1`).

## Root Cause Chain

### Layer 1: Wrong issue identifier on watchdog timeout

`MainAppStateController.performValidation()` uses a 12-second watchdog (`withThrowingTaskGroup` racing against `Task.sleep`). When the watchdog fires, the catch block created a `.component(.kanataService)` issue — the same identifier that triggers the "Kanata Service Stopped" alert via `handleKanataServiceIssueChange()` in `LiveKeyboardOverlayView`.

The timeout was caused by the **Helper** health check (Step 1), not Kanata. The watchdog didn't distinguish which step was slow.

### Layer 2: `getHelperHealth()` had massive redundancy

A single `getHelperHealth()` invocation called:

| Call | Count | Notes |
|------|-------|-------|
| `SMAppService.status` | up to 5x | Synchronous IPC to ServiceManagement daemon |
| `isHelperInstalled()` | up to 4x | Each calls SMAppService.status + potentially launchctl |
| `getHelperVersion()` | 2x | Cache was broken (see Layer 3) |
| XPC round-trips | 2x | One per getHelperVersion call |

Call graph:
```
getHelperHealth()
  ├─ SMAppService.status              [#1]
  ├─ isHelperInstalled()              [#1] → SMAppService.status [#2]
  ├─ getHelperVersion()
  │    ├─ isHelperInstalled()         [#2] → SMAppService.status [#3]
  │    └─ XPC getVersion()            [#1]
  └─ testHelperFunctionality()
       ├─ isHelperInstalled()         [#3] → SMAppService.status [#4]
       └─ getHelperVersion()
            ├─ isHelperInstalled()    [#4] → SMAppService.status [#5]
            └─ XPC getVersion()       [#2]
```

### Layer 3: `cachedHelperVersion` was never written

`getHelperVersion()` read `cachedHelperVersion` but never stored the result on success. Only `clearConnection()` touched it (to set nil). This forced every call through the full `isHelperInstalled()` + XPC path.

## Evidence (from keypath-debug.log)

Validation #57 timeline:
```
09:21:30.868  checkHelper() starts
09:21:41.618  getConnection() — reuse XPC (PID 14059)         [10.75s stall]
09:21:41.619  proxy.getVersion() dispatched
09:21:41.625  getVersion callback: 1.1.0                      [6ms XPC]
09:21:41.630  testHelperFunctionality() starts
09:22:17.930  getConnection() — reuse XPC (PID 14059)         [36.3s stall]
09:22:17.971  proxy.getVersion() dispatched
09:22:18.004  getVersion callback: 1.1.0                      [33ms XPC]
09:22:18.004  Helper state: healthy (v1.1.0)
09:22:18.005  Step 1 (Helper) completed in 47.137s
```

The XPC calls themselves were fast (6ms, 33ms). The stalls occurred in repeated `isHelperInstalled()` calls, likely due to slow `SMAppService.status` synchronous IPC under system load.

During the 36-second gap, only KanataEventListener events (~every 500ms) and LaunchDaemonPIDCache refreshes appeared in logs. No HelperManager activity at all.

Meanwhile the 12s watchdog fired and created the false alert.

## Fixes Applied

### Fix 1: Use `.validationTimeout` identifier (not `.component(.kanataService)`)

**File:** `MainAppStateController.swift`

The watchdog catch block now uses `.validationTimeout` — a new `IssueIdentifier` case that won't trigger the "Kanata Service Stopped" alert. Severity downgraded from `.critical` to `.warning` since this is transient.

### Fix 2: Eliminate redundant calls in `getHelperHealth()`

**File:** `HelperManager+Status.swift`

Removed `testHelperFunctionality()` from the `getHelperHealth()` hot path. A successful `getHelperVersion()` already proves XPC connectivity — if the helper returns a version string, it's functional. This cuts:
- `isHelperInstalled()` calls: 4 → 2
- `SMAppService.status` calls: 5 → 3
- XPC round-trips: 2 → 1

### Fix 3: Write to `cachedHelperVersion` on success

**File:** `HelperManager+Status.swift`

`getHelperVersion()` now stores the result in `cachedHelperVersion` after a successful XPC response. Subsequent calls return from cache instantly. Cache is still cleared by `clearConnection()`.

## Lessons Learned

1. **Check actual logs before theorizing.** Initial theory (PID file / launchctl transient failure) was wrong. The app debug log at `~/Library/Logs/KeyPath/keypath-debug.log` had the answer.

2. **Watchdog catch blocks must use accurate identifiers.** A generic timeout should never masquerade as a specific service failure.

3. **Synchronous Apple APIs (`SMAppService.status`) can block for arbitrary durations.** Never call them repeatedly in a hot path. Cache results or call once per validation cycle.

4. **Redundant work compounds under adverse conditions.** The helper check was designed for ~100ms but could take 47s because each subcall was repeated 2-5x, and any single slow call multiplied across all repetitions.

5. **Actor-isolated code with `nonisolated async` functions creates hidden scheduling dependencies.** The `isHelperInstalled()` stalls were invisible in logs because no code ran between the actor suspension and re-entry points.
