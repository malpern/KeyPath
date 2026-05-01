# Wizard State Refactor: Reactive Issues via @Observable

## Problem

Wizard pages receive `issues: [WizardIssue]` as `let` parameters — value snapshots captured at page construction. When the state machine updates after a refresh (e.g., user grants a permission and clicks Fix), pages don't see the change. The UI stays stale until the user navigates away and back.

Current workaround: Fix button navigates to summary page to force reconstruction with fresh data.

## Root Cause

```
WizardStateMachine (@Observable)
  └─ wizardIssues: [WizardIssue]  ← updates on refresh
       │
       ▼
InstallationWizardView (@State var stateMachine)
  └─ body re-evaluates when wizardIssues changes ✓
       │
       ▼
WizardInputMonitoringPage(issues: stateMachine.wizardIssues.filter {...})
  └─ self.issues = issues  ← let parameter, snapshot, FROZEN
       │
       ▼
Computed properties read self.issues  ← stale data
```

Pages also have `@Environment(WizardStateMachine.self)` but don't use it for issues.

## Proposed Fix

**Remove `issues` and `allIssues` parameters from all wizard pages. Pages read directly from the state machine via `@Environment`.**

### Before (every page)
```swift
public struct WizardInputMonitoringPage: View {
    public let issues: [WizardIssue]          // stale snapshot
    public let allIssues: [WizardIssue]       // stale snapshot
    
    private var kanataInputMonitoringStatus: InstallationStatus {
        stateInterpreter.getPermissionStatus(.kanataInputMonitoring, in: issues)
    }
}
```

### After (every page)
```swift
public struct WizardInputMonitoringPage: View {
    @Environment(WizardStateMachine.self) private var stateMachine
    
    private var permissionIssues: [WizardIssue] {
        stateMachine.wizardIssues.filter { $0.category == .permissions }
    }
    
    private var kanataInputMonitoringStatus: InstallationStatus {
        stateInterpreter.getPermissionStatus(.kanataInputMonitoring, in: permissionIssues)
    }
}
```

### Call site change (InstallationWizardView+UIComponents.swift)
```swift
// Before
WizardInputMonitoringPage(
    systemState: stateMachine.wizardState,
    issues: stateMachine.wizardIssues.filter { $0.category == .permissions },
    allIssues: stateMachine.wizardIssues,
    ...
)

// After
WizardInputMonitoringPage(
    systemState: stateMachine.wizardState,
    ...
)
```

## Scope

9 wizard pages need updating:

| Page | issues param | allIssues param |
|------|-------------|-----------------|
| WizardSummaryPage | ✓ remove | N/A |
| WizardFullDiskAccessPage | ✓ remove | N/A |
| WizardConflictsPage | ✓ remove | ✓ remove |
| WizardInputMonitoringPage | ✓ remove | ✓ remove |
| WizardAccessibilityPage | ✓ remove | ✓ remove |
| WizardKarabinerComponentsPage | ✓ remove | N/A |
| WizardHelperPage | ✓ remove | N/A |
| WizardKanataServicePage | ✓ remove | N/A |
| WizardCommunicationPage | ✓ remove | N/A |

## Benefits

1. **Reactive updates** — pages see fresh issues immediately when the state machine refreshes, no navigation needed
2. **Less plumbing** — removes `issues`/`allIssues` parameters from 9 pages and their call sites
3. **Single source of truth** — state machine is THE source, no stale snapshots
4. **Fix button works naturally** — `onRefresh()` updates state machine → page re-renders → UI shows green

## Risks

1. **Filter computation in body** — each page will recompute `stateMachine.wizardIssues.filter(...)` on every render. Mitigated: the array is tiny (<10 items), filter is O(n), negligible cost.
2. **Cascading re-renders** — any `wizardIssues` change re-renders all visible pages. Mitigated: only one page is visible at a time (tab-based wizard).
3. **Environment dependency** — pages require `WizardStateMachine` in environment. Already provided by parent view (line 145 of InstallationWizardView).

## Also remove the workaround

After this refactor, remove the `onNavigateToPage?(.summary)` calls added to the Fix buttons in WizardInputMonitoringPage and WizardAccessibilityPage — they'll no longer be needed since the page updates reactively.

## Implementation order

1. Update one page (WizardInputMonitoringPage) as proof of concept
2. Verify Fix button works without navigation workaround
3. Update remaining 8 pages
4. Remove `issues`/`allIssues` from page init signatures
5. Clean up call sites in UIComponents.swift
