# Karabiner Health Check False Positive - Investigation Report

**Date:** November 18, 2025
**Severity:** Medium - Blocks wizard completion, causes app to quit unexpectedly
**Status:** Root cause identified, fix plan ready for review

---

## Executive Summary

The KeyPath installation wizard incorrectly reports "Karabiner driver is still not healthy" with reason "service status check failed" even when all components are functioning correctly. This false positive occurs because the health check logic doesn't distinguish between two separate LaunchDaemon services with different lifecycle expectations:

1. **Daemon service** (`com.keypath.karabiner-vhiddaemon`) - Should stay running continuously
2. **Manager service** (`com.keypath.karabiner-vhidmanager`) - Runs once to activate driver, then exits (by design)

When users attempt to dismiss the error by clicking the X button, the wizard closes, which causes KeyPath to quit entirely.

---

## Evidence

### User-Reported Behavior

**Screenshot shows:**
```
Karabiner driver is still not healthy.

Reason: Daemon running (PID 52871) but
service status check failed.
This often indicates a stale service
registration, but the driver may still work.
PID: 52871
LaunchDaemon: installed, running
Driver extension: enabled
Driver version: 5.0.0
```

**User action:** Clicks X button to dismiss error
**Result:** KeyPath freezes/quits entirely

### System State Verification

**Process check:**
```bash
$ ps aux | grep -i karabiner | grep -v grep
root  53068  /Library/Application Support/org.pqrs/.../Karabiner-VirtualHIDDevice-Daemon
_driverkit  613  .../org.pqrs.Karabiner-DriverKit-VirtualHIDDevice.dext/...
```
✅ Daemon process running
✅ DriverKit extension running

**LaunchDaemon status:**
```bash
$ launchctl print system/com.keypath.karabiner-vhiddaemon
system/com.keypath.karabiner-vhiddaemon = {
    state = running
    active count = 1
}

$ launchctl print system/com.keypath.karabiner-vhidmanager
system/com.keypath.karabiner-vhidmanager = {
    state = not running
    active count = 0
}
```
✅ Daemon service: running (expected)
❌ Manager service: not running (wizard thinks this is a problem, but it's actually normal)

**System Extensions:**
```bash
$ systemextensionsctl list
enabled	active	teamID	bundleID (version)	name	[state]
*	*	G43BCU2T37	org.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.8.0/1.8.0)	[activated enabled]
```
✅ Driver extension activated

**Manager plist configuration:**
```xml
<key>KeepAlive</key>
<false/>
<key>RunAtLoad</key>
<true/>
```
**Important:** `KeepAlive=false` means the manager is **designed to exit** after running once.

**Manager logs:**
```
activation of org.pqrs.Karabiner-DriverKit-VirtualHIDDevice is requested
request of org.pqrs.Karabiner-DriverKit-VirtualHIDDevice is finished
request of org.pqrs.Karabiner-DriverKit-VirtualHIDDevice is completed
```
✅ Manager successfully activated the driver (multiple times), then exited as designed

### Conclusion from Evidence

**All components are healthy:**
- Daemon: Running ✅
- Driver: Activated ✅
- Manager: Ran successfully and exited (normal behavior) ✅

**Wizard incorrectly interprets:** Manager not continuously running = unhealthy state ❌

---

## Root Cause Analysis

### Code Locations

#### 1. VHIDDeviceManager.swift:213-219
```swift
func detectConnectionHealth() -> Bool {
    let isRunning = detectRunning()
    if !isRunning {
        AppLogger.shared.log("🔍 [VHIDManager] Process health check failed - daemon not running")
    }
    return isRunning  // ← Only checks if ANY process exists
}
```

**Problem:**
- Method name says "detectConnectionHealth" but only checks if process exists
- Doesn't distinguish between daemon and manager services
- Doesn't verify which process is actually running

#### 2. KanataManager.swift:2561-2564
```swift
} else {
    // Single PID = daemon process running but may have connection issues
    lines.append("Reason: Daemon running (PID \(status.pids[0])) but service status check failed.")
    lines.append("This often indicates a stale service registration, but the driver may still work.")
    lines.append("PID: \(status.pids[0])")
```

**Problem:**
- Assumes exactly 1 PID means "connection issues"
- In reality, 1 PID is the **expected state** (daemon running, manager exited)
- Error message is misleading - suggests something is broken when it's actually fine

#### 3. KarabinerComponentsStatusEvaluator.swift:43
```swift
case .component(.karabinerDriver),
     .component(.karabinerDaemon),
     .component(.vhidDeviceManager),
     .component(.vhidDeviceActivation),
     .component(.vhidDeviceRunning),
     .component(.launchDaemonServices),
     .component(.launchDaemonServicesUnhealthy),  // ← This gets triggered
     .component(.vhidDaemonMisconfigured),
     .component(.vhidDriverVersionMismatch):
    return true
```

**Problem:**
- `.launchDaemonServicesUnhealthy` issue is being created somewhere
- Evaluator treats this as a failure condition
- Causes wizard to show error toast

#### 4. InstallationWizardView.swift:609 & 713
```swift
if karabinerStatus != .completed {
    let detail = kanataManager.getVirtualHIDBreakageSummary()
    AppLogger.shared.log("❌ [Wizard] Post-fix (bulk) failed; showing diagnostic toast")
    await MainActor.run {
        toastManager.showError("Karabiner driver is still not healthy.\n\n\(detail)", duration: 7.0)
    }
}
```

**Problem:**
- Shows error toast when health check fails
- When user clicks X to dismiss, it closes the wizard sheet
- Closing wizard causes app to quit (wizard is the main window)

### Service Architecture

**Two separate services with different purposes:**

| Service | Purpose | KeepAlive | Expected State |
|---------|---------|-----------|----------------|
| `com.keypath.karabiner-vhiddaemon` | Daemon process that handles VirtualHID communication | (implied true) | Always running |
| `com.keypath.karabiner-vhidmanager` | Activates the DriverKit extension on boot | **false** | Runs once, then exits |

**Current health check:** Expects both to be running ❌
**Correct behavior:** Only daemon should be continuously running ✅

---

## Impact

### User Experience
1. **Blocks wizard completion** - Users can't proceed through installation
2. **Confusing error message** - Says "unhealthy" when everything works
3. **App quits unexpectedly** - Clicking X closes the app instead of dismissing error
4. **Loss of trust** - Users think something is broken when it's actually fine

### Technical Debt
1. **Misleading diagnostics** - Health check reports false positives
2. **Poor separation of concerns** - Manager vs daemon not distinguished
3. **Fragile wizard flow** - Error dialog dismissal shouldn't quit app

---

## Independent Assessment (Senior Developer Review)

**Reviewer Findings:**

After code review, the diagnosis is **correct** but the proposed solution is **more invasive than necessary**. Key findings:

### 1. Existing One-Shot Service Logic Already Exists

**Location:** `LaunchDaemonInstaller.swift:756-759`

```swift
if isOneShot {
    // One-shot: OK if clean exit or (still running) or within warm-up window
    if let lastExit, lastExit == 0 { healthy = true } else if isRunningLike || hasPID { healthy = true } else if inWarmup { healthy = true } // starting up
    else { healthy = false }
}
```

**Problem:** When `lastExit` is `nil` (no exit status in `launchctl print` output), all conditions fail and service is marked unhealthy.

### 2. Existing Workaround Should Prevent This Error

**Location:** `SystemSnapshotAdapter.swift:166-173`

```swift
if !snapshot.components.launchDaemonServicesHealthy {
    if snapshot.components.vhidDeviceHealthy {
         AppLogger.shared.log("📊 [SystemSnapshotAdapter]   LaunchDaemon services: UNHEALTHY (but daemon running) - Downgrading to non-blocking")
         // Do NOT add to missing components list if the daemon is actually running
    } else {
        AppLogger.shared.log("📊 [SystemSnapshotAdapter]   LaunchDaemon services: UNHEALTHY")
        missing.append(.launchDaemonServices)
    }
}
```

**Key Questions:**
- Why isn't this workaround preventing the error?
- Is `vhidDeviceHealthy` returning false? If so, why?

### 3. Root Issue: `allServicesHealthy` Check

**Location:** `LaunchDaemonInstaller.swift:2868-2870`

```swift
var allServicesHealthy: Bool {
    kanataServiceHealthy && vhidDaemonServiceHealthy && vhidManagerServiceHealthy
}
```

**Problem:** Requires ALL THREE services including manager to be healthy, even though manager is designed to exit.

---

## Revised Solution (Surgical Approach)

### Phase 1: Fix `isServiceHealthy()` for One-Shot Services (PRIORITY)

**File:** `LaunchDaemonInstaller.swift:756-759`

**Change from:**
```swift
if isOneShot {
    // One-shot: OK if clean exit or (still running) or within warm-up window
    if let lastExit, lastExit == 0 { healthy = true } else if isRunningLike || hasPID { healthy = true } else if inWarmup { healthy = true } // starting up
    else { healthy = false }
}
```

**To:**
```swift
if isOneShot {
    // One-shot services run once and exit - this is normal
    if let lastExit {
        // If we have exit status, it must be clean (0)
        healthy = (lastExit == 0)
    } else if isRunningLike || hasPID || inWarmup {
        // Service currently running or starting up
        healthy = true
    } else {
        // No exit status and not running - assume it ran successfully
        // This is normal for one-shot services that run at boot
        AppLogger.shared.log("🔍 [LaunchDaemon] One-shot service \(serviceID) not running (normal) - assuming healthy")
        healthy = true
    }
}
```

**Rationale:**
- More lenient when `lastExit` is nil (common for one-shot services)
- Preserves existing architecture
- Surgical fix - only changes the problematic condition
- Logs clearly when assuming healthy state

### Phase 2: Fix Error Message

**File:** `KanataManager.swift` (around line 2561)

**Change from:**
```swift
} else {
    // Single PID = daemon process running but may have connection issues
    lines.append("Reason: Daemon running but connection issues detected.")
```

**To:**
```swift
} else if status.pids.count == 1 {
    // Single PID is normal - only the daemon should be running continuously
    // The manager service runs once and exits (KeepAlive=false)
    lines.append("Daemon: Running (PID \(status.pids[0]))")
    lines.append("Manager: Runs on-demand (exits after activation)")
    lines.append("Status: Healthy")

    // Only flag as unhealthy if we can't verify it's the daemon
    if let owner = status.owners.first, !owner.contains("Karabiner-VirtualHIDDevice-Daemon") {
        lines.append("⚠️ Warning: Process may not be the expected daemon")
    }
}
```

**Rationale:**
- Clarifies that single PID is the expected state
- Explains manager service behavior
- Only shows warning if process isn't the daemon

### Phase 3: Investigate SystemSnapshotAdapter Workaround (CRITICAL)

**File:** `SystemSnapshotAdapter.swift:166-173`

**Investigation needed:**
1. Why isn't the existing workaround preventing the error?
2. Is `snapshot.components.vhidDeviceHealthy` returning false?
3. If false, what causes `vhidDeviceHealthy` to fail?

**Add diagnostic logging:**
```swift
if !snapshot.components.launchDaemonServicesHealthy {
    // NEW: Log the state of vhidDeviceHealthy to understand workaround behavior
    AppLogger.shared.log("📊 [SystemSnapshotAdapter] vhidDeviceHealthy = \(snapshot.components.vhidDeviceHealthy)")

    if snapshot.components.vhidDeviceHealthy {
        AppLogger.shared.log("📊 [SystemSnapshotAdapter]   LaunchDaemon services: UNHEALTHY (but daemon running) - Downgrading to non-blocking")
        // Do NOT add to missing components list if the daemon is actually running
    } else {
        AppLogger.shared.log("📊 [SystemSnapshotAdapter]   LaunchDaemon services: UNHEALTHY")
        missing.append(.launchDaemonServices)
    }
}
```

### Phase 4: Add Diagnostic Logging

**Add to health check:**
```swift
AppLogger.shared.log("🔍 [VHIDManager] Health Check:")
AppLogger.shared.log("  - Daemon (vhiddaemon): \(daemonRunning ? "running" : "not running")")
AppLogger.shared.log("  - Manager (vhidmanager): runs on-demand, exits after activation")
AppLogger.shared.log("  - Driver Extension: \(driverActivated ? "activated" : "not activated")")
AppLogger.shared.log("  - Overall Health: \(isHealthy ? "HEALTHY" : "UNHEALTHY")")
```

**Rationale:**
- Makes it clear which component is being checked
- Documents expected behavior (manager exits)
- Easier to debug future issues

---

## Testing Plan

### Test Cases

#### 1. Fresh Install
**Setup:** Clean system, no Karabiner components
**Expected:** Wizard installs both services, activates driver, shows success
**Verify:** No false positive health errors

#### 2. Manager Not Running (Normal State)
**Setup:** Daemon running, manager exited, driver activated
**Expected:** Health check passes, wizard shows success
**Verify:** This is the scenario that currently fails - should now pass

#### 3. Daemon Not Running (Actual Problem)
**Setup:** Stop daemon service, manager exited
**Expected:** Health check fails, wizard shows actionable error
**Verify:** Fix button restarts daemon successfully

#### 4. Driver Not Activated
**Setup:** Services running but driver not activated
**Expected:** Health check fails, wizard shows error
**Verify:** Fix button activates driver

#### 5. Error Dialog Dismissal
**Setup:** Any error shown in toast
**Expected:** Clicking X dismisses error without closing wizard
**Verify:** App stays open, wizard remains accessible

---

## Open Questions

### Critical (Blocking Implementation)

1. **Why isn't SystemSnapshotAdapter workaround working?**
   - Code at lines 166-173 should prevent error if `vhidDeviceHealthy` is true
   - Need to verify: Is `vhidDeviceHealthy` returning false? If so, why?
   - Is `VHIDDeviceManager.detectConnectionHealth()` failing?
   - This must be answered before implementing Phase 1 fix

### Important (Should Address)

2. **Why does clicking X close the wizard/app?**
   - Is this a SwiftUI sheet behavior?
   - Should we prevent sheet dismissal when errors are shown?
   - Or should we make wizard closure not quit the app?

3. **Version mismatch (1.8.0 vs 5.0.0)?**
   - `systemextensionsctl` shows version 1.8.0 installed
   - Wizard screenshot shows version 5.0.0
   - Is this a display bug or actual mismatch?
   - If mismatch, should we also fix version detection?

### Low Priority

4. **Should manager service plist have better documentation?**
   - Current plist has `<key>KeepAlive</key><false/>`
   - This is correct behavior
   - Should add comments explaining one-shot design?

---

## Risk Assessment (Revised for Surgical Approach)

### Low Risk Changes (Recommended)
- ✅ Fix `isServiceHealthy()` one-shot logic (Phase 1)
  - **Impact:** Minimal - only affects one-shot service health determination
  - **Risk:** Low - makes logic more lenient, won't break existing behavior
  - **Mitigation:** Extensive logging, existing tests should cover edge cases

- ✅ Update error message wording (Phase 2)
  - **Impact:** User-facing text only
  - **Risk:** Very low - cosmetic change
  - **Mitigation:** Review message with stakeholders

- ✅ Add diagnostic logging (Phase 3, 4)
  - **Impact:** Log output only
  - **Risk:** None - informational only
  - **Mitigation:** N/A

### Medium Risk Changes (Investigation Needed)
- ⚠️ Investigate SystemSnapshotAdapter workaround failure (Phase 3)
  - **Impact:** May reveal deeper architectural issues
  - **Risk:** Medium - requires understanding why existing workaround failed
  - **Mitigation:** Add logging first, observe behavior before making changes

### High Risk Changes (Out of Scope)
- 🔴 Change wizard sheet dismissal behavior
  - **Impact:** Could affect other wizard flows
  - **Recommendation:** Defer to separate fix

- 🔴 Rewrite `detectConnectionHealth()` (original proposal)
  - **Impact:** Too invasive, existing architecture already handles one-shot services
  - **Recommendation:** Use surgical fix instead

---

## Recommended Next Steps (Revised)

### Immediate Actions (Before Code Changes)

1. ✅ **Review this analysis** - Root cause assessment confirmed accurate by senior developer
2. ✅ **Independent assessment complete** - Surgical approach approved
3. 🔍 **CRITICAL: Investigate SystemSnapshotAdapter workaround**
   - Add logging to verify `vhidDeviceHealthy` value
   - Understand why existing workaround at lines 166-173 isn't preventing error
   - This must be done BEFORE implementing Phase 1 fix

### Implementation (After Investigation)

4. **Implement Phase 1** - Fix `isServiceHealthy()` one-shot logic (surgical approach)
5. **Implement Phase 2** - Fix error message in `getVirtualHIDBreakageSummary()`
6. **Implement Phase 3 & 4** - Add diagnostic logging
7. **Test thoroughly** - Run through all test cases
8. **Document** - Update CLAUDE.md with findings (new ADR if needed)

### Key Difference from Original Plan

**Original proposal:** Rewrite `VHIDDeviceManager.detectConnectionHealth()` to only check daemon process

**Revised approach:** Fix `LaunchDaemonInstaller.isServiceHealthy()` to be more lenient for one-shot services when `lastExit` is nil

**Why better:** Preserves existing architecture, more surgical, less risky

---

## Additional Context

### Related Code Locations

**Health check callers:**
- `InstallationWizardView.swift:605-713` - Shows error toast when health check fails
- `KarabinerComponentsStatusEvaluator.swift:33-55` - Evaluates Karabiner health
- `WizardStateInterpreter.swift:148-167` - Filters Karabiner-related issues

**Service management:**
- `/Library/LaunchDaemons/com.keypath.karabiner-vhiddaemon.plist`
- `/Library/LaunchDaemons/com.keypath.karabiner-vhidmanager.plist`
- `LaunchDaemonInstaller.swift` - Installs service plists

### Historical Context

**From investigation:**
- Issue has been present since Karabiner driver integration
- Manager service `KeepAlive=false` is intentional design
- Health check logic was written assuming both services stay running
- Error messaging assumes single PID = problem state

**Impact on users:**
- Blocking issue for new installations
- Confusing UX (shows error when everything works)
- Loss of trust in wizard diagnostics

---

## Summary of Assessment

### Agreement Points
- ✅ Root cause diagnosis is **accurate**
- ✅ Evidence is **comprehensive**
- ✅ Problem understanding is **correct**

### Disagreement Points
- ❌ Original proposed solution was **too invasive**
- ❌ Didn't leverage **existing one-shot service logic**
- ❌ Ignored **existing SystemSnapshotAdapter workaround**

### Recommended Approach
1. **First priority:** Understand why SystemSnapshotAdapter workaround isn't working
2. **Surgical fix:** Update `isServiceHealthy()` to be more lenient when `lastExit` is nil
3. **Preserve architecture:** Use existing patterns instead of rewriting health check logic

### Critical Insight
The codebase ALREADY has the right architecture for handling one-shot services. The bug is in a single edge case (nil `lastExit`), not a fundamental design flaw. Fix the edge case, don't rewrite the system.

---

## Contact

**Prepared by:** Claude Code (AI Assistant)
**Investigation Date:** November 18, 2025
**Reviewed by:** Senior Developer (Independent Assessment Completed)
**Status:**
- ✅ Root cause confirmed
- ✅ Surgical approach approved
- 🔍 Investigation phase: Why isn't SystemSnapshotAdapter workaround working?
- ⏳ Implementation pending investigation results
