# Wizard Toast Refactor Plan

## Problem Statement

The installation wizard currently uses toast notifications (floating overlays) to communicate status updates like "Verifying...", "Success", and error messages. This creates visual clutter and doesn't feel integrated with the wizard flow. Users should see status updates inline within the wizard page itself.

## Current State

Toast usage across wizard pages (30+ occurrences):

### WizardKanataServicePage.swift
- `showSuccess("\(actionName) succeeded")` - after start/stop/restart
- `showError("\(actionName) failed: \(error)")` - on failure

### WizardKarabinerComponentsPage.swift
- `showError(...)` - driver repair failures

### WizardHelperPage.swift
- `showError(lastError ?? "Helper install failed")` - helper installation failure

### InstallationWizardView.swift (majority of toasts)
- `showInfo("Another fix is already running...")` - concurrent fix prevention
- `showInfo("Verifying...")` - during verification
- `showSuccess("Issues resolved")` - after successful fix
- `showSuccess("Kanata service started/recovered")` - service status
- `showError("Repair failed: ...")` - various error states
- `showInfo("No issues found to repair")` - nothing to fix
- `showInfo("Fix already running...")` - duplicate fix prevention
- `showSuccess("KeyPath approved in Login Items")` - SMAppService approval
- `showInfo("Login Items check timed out...")` - timeout states

## Proposed Solution

### 1. Add Status State to WizardHeroSection

Extend `WizardHeroSection` to support an optional status message that appears below the subtitle:

```swift
struct WizardHeroSection: View {
    // Existing properties...
    var statusMessage: String? = nil
    var statusType: StatusType = .info  // .info, .success, .error, .progress

    enum StatusType {
        case info, success, error, progress

        var color: Color { ... }
        var icon: String? { ... }
    }
}
```

### 2. Add Page-Level Status State

Each wizard page that performs actions should have:

```swift
@State private var actionStatus: ActionStatus = .idle

enum ActionStatus {
    case idle
    case inProgress(message: String)
    case success(message: String)
    case error(message: String)

    var isActive: Bool { ... }
    var message: String? { ... }
}
```

### 3. Status Display in Hero Section

The status appears as an animated row below the subtitle:
- Progress: Spinner + message
- Success: Checkmark + message (auto-dismisses after 3s)
- Error: Warning icon + message (stays until next action)

### 4. Migration Strategy

#### Phase 1: Add Infrastructure ✅ COMPLETE
- [x] Add `statusMessage` and `statusType` to `WizardHeroSection`
- [x] Create `ActionStatus` enum in a shared location (`WizardDesign.ActionStatus`)
- [x] Add status animation/transition support
- [x] Create `InlineStatusView` component in `WizardHeroSection.swift`

#### Phase 2: Migrate Page by Page ✅ COMPLETE (pages only)
- [x] `WizardKanataServicePage` - Replace toasts with inline status
- [x] `WizardKarabinerComponentsPage` - Replace toasts with inline status
- [x] `WizardHelperPage` - Replace toasts with inline status
- [N/A] `InstallationWizardView` main actions - KEEP AS TOASTS (global/cross-page notifications)

#### Phase 3: Cleanup (OPTIONAL)
- [x] Remove `toastManager` parameter from migrated pages
- [ ] Consider removing `WizardToastManager` entirely if unused
- [ ] Update any remaining edge cases

**Note:** InstallationWizardView toasts were intentionally kept as they handle:
- Global auto-fix operations spanning multiple pages
- Cross-page notifications (service recovery, Login Items approval)
- "Fix already running" guards at container level
These match the "Keep toasts for" criteria in the design considerations.

### 5. Design Considerations

**Keep toasts for:**
- Global errors that aren't page-specific
- Notifications that need to persist across page navigation

**Use inline status for:**
- Action feedback (start, stop, fix, verify)
- Progress indication during operations
- Success/failure of page-specific operations

### 6. Example Implementation

```swift
// In WizardKanataServicePage
var body: some View {
    VStack(spacing: WizardDesign.Spacing.sectionGap) {
        WizardHeroSection(
            icon: "gearshape.2",
            iconColor: serviceStatus.color,
            overlayIcon: serviceStatus.icon,
            overlayColor: serviceStatus.color,
            overlaySize: .large,
            title: "Kanata Service",
            subtitle: statusMessage,
            statusMessage: actionStatus.message,  // NEW
            statusType: actionStatus.type,        // NEW
            iconTapAction: { refreshStatus() }
        )
        // ...
    }
}

private func startService() {
    actionStatus = .inProgress(message: "Starting Kanata service...")

    Task { @MainActor in
        let success = await kanataManager.startKanata(reason: "Wizard")
        if success {
            actionStatus = .success(message: "Service started successfully")
            // Auto-clear after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            if case .success = actionStatus { actionStatus = .idle }
        } else {
            actionStatus = .error(message: "Failed to start service")
        }
    }
}
```

## Files to Modify

1. `Sources/KeyPathAppKit/InstallationWizard/UI/Components/WizardHeroSection.swift`
2. `Sources/KeyPathAppKit/InstallationWizard/UI/Pages/WizardKanataServicePage.swift`
3. `Sources/KeyPathAppKit/InstallationWizard/UI/Pages/WizardKarabinerComponentsPage.swift`
4. `Sources/KeyPathAppKit/InstallationWizard/UI/Pages/WizardHelperPage.swift`
5. `Sources/KeyPathAppKit/InstallationWizard/UI/InstallationWizardView.swift`

## Estimated Scope

- Infrastructure (Phase 1): ~100 lines
- Per-page migration (Phase 2): ~50-100 lines per page
- Cleanup (Phase 3): Net reduction

Total: Medium-sized refactor, can be done incrementally page-by-page.
