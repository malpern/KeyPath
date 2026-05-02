# Wizard Architecture Audit & Reunification Plan

## Executive Summary

The wizard and system health infrastructure has seven core problems caused by organic growth and incremental patching. What was once a single validation → issue → UI pipeline has fragmented into parallel paths that disagree on system state, use different issue identifiers, apply different grace periods, and parse the same log files with different patterns. The result: the wizard can show green while Settings shows red, permission pages show the wrong permission as broken, and the Fix button loops without effect.

This document catalogs every fragmentation point, then proposes a concrete reunification that collapses parallel paths back to shared single sources.

---

## Problem 1: Two SystemValidator Instances

**Current state:**
- `MainAppStateController.configure()` creates its own `SystemValidator` (search: `SystemValidator()` in `MainAppStateController.configure()`)
- The wizard uses `WizardDependencies.systemValidator` set at app startup (search: `systemValidator` in `WizardProtocolConformances`)
- These are **separate instances** — `SystemValidator`'s single-flight guard (`inProgressValidation`) only protects within one instance

**Impact:** Concurrent validations when MainAppStateController's periodic refresh and the wizard's state detection both fire. Wasted work, potential for race conditions.

**Fix:** One shared `SystemValidator` instance. MainAppStateController should receive it via DI (same instance set in `WizardDependencies`), not create its own.

---

## Problem 2: Three-Layer Type Conversion with Information Loss

**Current state:**
```
SystemValidator.checkSystem()
  → SystemSnapshot          (pure value, all health/permission/component data)
    → SystemContext          (InstallerEngine wraps snapshot, adds EngineSystemInfo)
      → SystemStateResult   (SystemContextAdapter.adapt() — wizard state + issues)
```

Each conversion reinterprets data:
- `SystemSnapshot.blockingIssues` treats `.unknown` kanata permissions as blocking (`!isReady`)
- `SystemContextAdapter.adaptIssues()` treats `.unknown` as a warning (not blocking)
- These produce different issue lists from the same snapshot

**Impact:** Debugging requires tracing through three type conversions to find where a classification went wrong.

**Fix:** Eliminate `SystemContext` as a separate type. `SystemContextAdapter` should operate directly on `SystemSnapshot`. `InstallerEngine.inspectSystem()` becomes a thin wrapper that calls `SystemValidator.checkSystem()` and adapts inline. No intermediate type.

---

## Problem 3: Settings Status Tab Has Independent Validation

**Current state:**
- Settings Status runs its own `refreshStatus()` (search: `refreshStatus()` in `SettingsView`)
- Tries `MainAppStateController.shared.lastValidatedSystemContext` first
- Falls back to `kanataManager.inspectSystemContext()` — **known broken** (comment in code: "initialized before WizardDependencies.systemValidator was set, so it always returns empty context")
- Has its own `checkTCPConfiguration()` duplicate
- Has its own 1-second retry for "starting" state

**Impact:** Settings can show different state than the wizard and overlay. The broken fallback path means Settings can show "no issues" when there are real issues.

**Fix:** Settings Status tab should ONLY consume `MainAppStateController`'s published state. No independent validation, no fallback path, no duplicate TCP check. `MainAppStateController` is THE single publisher; all UI surfaces are consumers.

---

## Problem 4: Hardcoded Issues Bypass SystemContextAdapter

**Current state:** `MainAppStateController.performValidation()` generates issues in three places that bypass `SystemContextAdapter`:

1. **Validator not configured** (search: `"System validator not configured"` in `performValidation()`): Creates `.daemon` category issue
2. **Startup gate failure** (search: `"Kanata service not healthy"` in `performValidation()`): Creates `.component(.keyPathRuntime)` issue
3. **Validation timeout** (search: `.validationTimeout` in `performValidation()`): Creates `.validationTimeout` issue

These use identifiers and categories that `SystemContextAdapter` never produces.

**Impact:** The overlay and Settings tab must handle these special-case issues separately. The wizard's `WizardNavigationEngine` doesn't know about `.validationTimeout` — it falls through to default handling. The "1 setup issue" shown in Settings during the user's testing was the startup gate's hardcoded issue, completely independent of the wizard's SystemValidator result.

**Fix:** All issues flow through `SystemContextAdapter`. The startup gate, timeout, and not-configured states should produce `SystemContext` values that the adapter converts to standard `WizardIssue` types. No hardcoded issue construction outside the adapter.

---

## Problem 5: Startup Grace Period Inconsistency

**Current state:** Three different surfaces, three different grace behaviors:

| Surface | Grace period | Source |
|---------|-------------|--------|
| Overlay | 140 seconds | `TransientStartupWindowEvaluator` via `MainAppStateController.isInRuntimeStartupWindow()` |
| Settings Status | **None** | Runs `SystemContextAdapter.adapt()` directly, no suppression |
| MainAppStateController startup gate | 3s definitive / 130s transient | `evaluateKanataStartupGate()` with its own timing constants |

**Impact:** Within the first ~2 minutes after launch: overlay shows "checking" (suppressed), Settings shows "1 issue" (not suppressed), wizard shows "KeyPath Runtime running" (from SystemValidator which says healthy). Three surfaces, three states.

**Fix:** One grace period, applied at the `MainAppStateController` level before publishing. All consumers see the same state. During the grace window, the published state is `.starting` (not `.failed`). After the window, if still unhealthy, publish `.failed`. No per-consumer suppression.

---

## Problem 6: Two Stderr Parsers with Overlapping Scopes

**Current state:**

| Parser | File | Reads | Pattern | Returns |
|--------|------|-------|---------|---------|
| `checkDaemonStderrForPermissionFailure()` | SystemValidator | Last 2KB | `"kanata needs macOS Accessibility permission"` OR `"IOHIDDeviceOpen error" + "not permitted"` | `Bool` → `kanataPermissionRejected` |
| `checkKanataInputCaptureStatus()` | ServiceHealthChecker | Last 64KB | `"iohiddeviceopen error" + "not permitted" + "apple internal keyboard / trackpad"` | `KanataInputCaptureStatus` → `kanataInputCaptureReady` |

A third permission source — `PermissionOracle.checkTCCForKanata()` — queries the TCC database (not stderr) and is not part of this problem, but adds to the overall fragmentation: three different data sources for permission state.

The two stderr parsers read the **same file** with **different tail sizes** and **overlapping patterns**. A manual suppression in SystemValidator forces `inputCaptureReady = true` when `permissionRejected` is true to avoid double-counting.

**Impact:** Every new stderr pattern requires updating multiple parsers. The suppression logic is fragile — if either parser's pattern matching changes, the suppression breaks and the wrong permission shows as failed.

**Fix:** As documented in `docs/architecture/wizard-permission-architecture.md`: one `diagnoseDaemonStderr()` function that reads the log once, classifies all known error patterns, and returns a single structured `KanataDaemonDiagnosis`. No suppression needed because classification is correct the first time.

---

## Problem 7: Six Independent Refresh/Polling Mechanisms

| Mechanism | Interval | What it does |
|-----------|----------|-------------|
| MainAppStateController service health poll | 2 seconds | Polls `kanataManager.currentRuntimeStatusInternal()`, triggers `revalidate()` on transition |
| MainAppStateController periodic refresh | 60 seconds | Triggers `revalidate()` if last validation >30s old |
| MainAppStateController error notification | On event | Listens for `.kanataErrorDetected`, triggers immediate `revalidate()` |
| Wizard `monitorSystemState()` | 60 seconds | Only on summary page, runs `performSmartStateCheck()` |
| Overlay health observer | 250ms | Polls `MainAppStateController.validationState` and `.issues` |
| Settings Status `refreshStatus()` | Manual | No polling, triggered by view appear / user action |

**Impact:** MainAppStateController's 2s poll and 60s refresh can both call `revalidate()` near-simultaneously. The wizard's monitor runs independently. The overlay polls at 250ms, briefly showing "checking" during routine refreshes.

**Fix:** MainAppStateController is the single poller/refresher. It publishes state via `@Observable` properties. All consumers (wizard, overlay, Settings) observe those properties reactively. No independent refresh mechanisms. The wizard's `monitorSystemState()` is deleted — the wizard reads from `@Environment(MainAppStateController.self)` or receives state via the existing callback/notification mechanism.

---

## The Correct Architecture

```
                    ┌──────────────────────────┐
                    │     SystemValidator       │  ← ONE shared instance
                    │  (the only validator)     │
                    └────────────┬─────────────┘
                                 │ SystemSnapshot
                                 ▼
                    ┌──────────────────────────┐
                    │   SystemContextAdapter    │  ← THE ONLY issue generator
                    │  (snapshot → state+issues)│
                    └────────────┬─────────────┘
                                 │ (WizardSystemState, [WizardIssue])
                                 ▼
                    ┌──────────────────────────┐
                    │  MainAppStateController   │  ← THE ONLY publisher
                    │  - owns the validator     │
                    │  - applies grace period   │
                    │  - publishes state        │
                    │  - NO hardcoded issues    │
                    └────────┬──────┬──────┬───┘
                             │      │      │
                    ┌────────┘      │      └────────┐
                    ▼               ▼               ▼
              ┌──────────┐  ┌──────────────┐  ┌──────────┐
              │  Wizard   │  │   Overlay    │  │ Settings │
              │  (reads)  │  │   (reads)    │  │  (reads) │
              └──────────┘  └──────────────┘  └──────────┘
```

**Key invariants:**
1. One `SystemValidator` instance, shared by all consumers
2. One issue generation path (`SystemContextAdapter`), no bypass
3. One publisher (`MainAppStateController`), no independent validation
4. One grace period, applied before publishing
5. One stderr parser, producing structured classification
6. All UI surfaces are read-only consumers of published state

---

## Migration Path

### Phase 1: Single SystemValidator instance ✅ DONE
- MainAppStateController receives validator via DI instead of creating its own
- Verify single-flight protection works across all callers

### Phase 2: Eliminate hardcoded issues ✅ DONE
- Startup gate failure → produce a `SystemContext` with `kanataRunning=false`, let adapter classify
- Validation timeout → `SystemContext.timedOut` flag, adapter produces `.validationTimeout` issue
- Not-configured → early return with empty state, no issues

### Phase 3: Settings Status consumes MainAppStateController only ✅ DONE
- Deleted `refreshStatus()` independent validation, fallback path, and duplicate TCP check
- Settings reads from `MainAppStateController` published state only

### Phase 4: Unified startup grace period ✅ DONE
- MainAppStateController applies grace period BEFORE publishing state
- During grace window, published state is `.checking` not `.failed`
- Deleted overlay-specific `inStartupWindow` suppression logic

### Phase 5: Unified stderr parser ✅ DONE
- Created `KanataDaemonDiagnosis` and `diagnoseDaemonStderr()`
- Deleted `checkDaemonStderrForPermissionFailure()` and `checkKanataInputCaptureStatus()`
- AX rejection automatically suppresses IM diagnosis (no manual suppression needed)
- Also fixed: only scans errors from most recent kanata launch (stale log entries ignored)

### Phase 6: Delete wizard's independent refresh (DEFERRED)
- **Status:** Deferred — requires cross-module wiring. The wizard (`KeyPathInstallationWizard`) cannot import `MainAppStateController` (`KeyPathAppKit`). Eliminating the wizard's monitor requires publishing state via a protocol, notification, or callback across the module boundary.
- **Mitigated by Phase 1:** The wizard's monitor now uses the shared `SystemValidator` instance, so its 60s poll benefits from single-flight dedup and produces consistent results.
- Delete `monitorSystemState()` from WizardStateMachine
- Wizard reads from `MainAppStateController` via environment or notification
- **Risk:** Medium — requires cross-module architecture change, not just code deletion
- **Rollback:** Restore `monitorSystemState()` — it's independent and doesn't conflict with the centralized path.

### Phase 7: Eliminate SystemContext intermediate type (optional)
- `SystemContextAdapter` operates on `SystemSnapshot` directly
- `InstallerEngine.inspectSystem()` returns adapted result
- **Risk:** High (wide API change) — defer to later if needed
- **Rollback:** Keep `SystemContext` as a pass-through wrapper. This is a refactor, not a behavior change, so revert is mechanical.

---

## Tests to Add

Each phase should include tests that verify the invariant it establishes. The test is the definition of done for that phase.

| Phase | Test | Done when |
|-------|------|-----------|
| 1 | Test that MainAppStateController and wizard produce identical snapshots from a single shared validator | No second `SystemValidator()` constructor call exists outside DI setup |
| 2 | Test that every issue in `MainAppStateController.issues` has an identifier that `WizardNavigationEngine` handles | No issue construction outside `SystemContextAdapter` |
| 3 | Test that Settings Status shows the same state as MainAppStateController | `refreshStatus()` and fallback path deleted |
| 4 | Test that overlay, Settings, and wizard all show the same state at T=0, T=60, T=150 after launch | No per-surface grace/suppression logic remains |
| 5 | Test all known stderr patterns → correct diagnosis (AX vs IM vs startup failure) | Single `diagnoseDaemonStderr()` function, old parsers deleted |
| 6 | Test that wizard state changes only when MainAppStateController publishes | `monitorSystemState()` deleted |
| 7 | (Optional) Test that `SystemContextAdapter` accepts `SystemSnapshot` directly | `SystemContext` type deleted or reduced to type alias |
