# Permission Pages: Oracle-Direct Display

## Problem

The wizard's permission pages (Accessibility, Input Monitoring) determine their display state (`?` / green / red) by:
1. Polling the Oracle every 500ms for permission changes
2. When a change is detected, calling `onRefresh()` which triggers full system validation (~2s)
3. Full validation updates `stateMachine.wizardIssues`
4. The page reads `wizardIssues` to compute `kanataAccessibilityStatus` etc.

This round-trip causes three bugs:
- **Page churn**: `onRefresh()` can trigger navigation re-evaluation, causing `onDisappear` → polling cancelled → stale display
- **Latency**: 2-second delay between Oracle detecting grant and UI updating
- **False negatives**: If validation produces issues for other reasons (IM unknown), the AX status shows `?` even when AX is granted

## Solution

Permission pages read the Oracle snapshot directly for their display state. No issue-list intermediary. `onRefresh()` only fires when all permissions on the page are granted (to trigger navigation advancement).

## Changes

### Per permission page (Accessibility + Input Monitoring):

**1. Add an `@State` property for the Oracle snapshot:**
```swift
@State private var permissionSnapshot: PermissionOracle.Snapshot?
```

**2. Replace issue-based status computation with Oracle-direct:**

Before:
```swift
private var kanataAccessibilityStatus: InstallationStatus {
    stateInterpreter.getPermissionStatus(.kanataAccessibility, in: issues)
}
```

After:
```swift
private var kanataAccessibilityStatus: InstallationStatus {
    guard let snapshot = permissionSnapshot else { return .inProgress }
    switch snapshot.kanata.accessibility {
    case .granted: return .completed
    case .denied, .error: return .failed
    case .unknown: return .warning
    }
}
```

Same pattern for `keyPathAccessibilityStatus`, `kanataInputMonitoringStatus`, `keyPathInputMonitoringStatus`.

**3. Simplify passive polling to update the snapshot, not call onRefresh:**

Before:
```swift
// polls Oracle → detects change → calls onRefresh() → full validation → issues update → display updates
```

After:
```swift
// polls Oracle → updates @State permissionSnapshot → SwiftUI re-renders directly
// only calls onRefresh() when ALL permissions on this page are granted (to advance navigation)
```

```swift
permissionPollingTask = Task { @MainActor in
    while !Task.isCancelled {
        _ = await WizardSleep.ms(500)
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        permissionSnapshot = snapshot

        let allGranted = snapshot.keyPath.accessibility.isReady 
                      && snapshot.kanata.accessibility.isReady
        if allGranted {
            await onRefresh()  // trigger navigation advancement
            return
        }
    }
}
```

**4. `hasAccessibilityIssues` derives from snapshot, not issues:**

Before:
```swift
private var hasAccessibilityIssues: Bool {
    keyPathAccessibilityStatus != .completed || kanataAccessibilityStatus != .completed
}
```

This stays the same — it already delegates to the status properties which now read from the snapshot.

**5. Remove `stateInterpreter` usage for permission status on these pages.**

The `stateInterpreter.getPermissionStatus()` path is no longer used for display. It can remain for other pages that still use issue-based status.

### Files changed:
- `WizardAccessibilityPage.swift` (~30 lines changed)
- `WizardInputMonitoringPage.swift` (~30 lines changed)

### Files NOT changed:
- `SystemContextAdapter` — still generates permission issues for navigation/summary
- `WizardStateMachine` — still runs full validation for page routing
- `WizardStateInterpreter` — still exists for component/service status
- `PermissionOracle` — no changes needed
- `MainAppStateController` — no changes needed

## Why This Is the Right Final Answer

1. **Direct data source**: Permission pages read from the authority (Oracle) instead of a derived signal (issues). No information loss, no latency.

2. **No new abstractions**: No protocols, no cross-module wiring, no DI changes. The Oracle is already importable from the wizard module.

3. **Clean separation**: Oracle for real-time display. Full validation for navigation decisions. Each concern uses the right tool.

4. **No state machine changes**: The wizard's navigation logic still works the same way — `onRefresh()` triggers full validation, state machine decides the next page. We just decoupled the *display* from the *navigation*.

## Verification

After implementation:
1. Grant KeyPath AX → green check appears within 1 second (no Fix click needed)
2. Grant kanata-launcher AX → green check appears within 1 second
3. Both granted → page auto-advances to next step
4. Revoke permission in System Settings → status flips back to red/orange
5. Summary page still shows correct state (uses issue-based display, unchanged)
6. Navigation still routes to correct page (uses full validation, unchanged)
