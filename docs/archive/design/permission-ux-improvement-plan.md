# Permission UX Improvement Plan: Three-Phase Implementation

## Executive Summary

This plan outlines a three-phase approach to modernize KeyPath's permission handling, moving from the current manual System Settings flow to Apple's recommended just-in-time permission requests with automatic prompts.

**Current State**: Manual 7-step System Settings flow (poor UX)  
**Target State**: Automatic prompts + just-in-time requests + optional wizard (modern Mac app UX)

---

## Phase 1: Automatic Permission Prompts (Immediate Improvement)

### Goal
Replace manual System Settings navigation with automatic system permission dialogs using Apple's standard APIs.

### Important Constraints (Kanata)
- Auto-prompt APIs (`IOHIDRequestAccess`, `AXIsProcessTrustedWithOptions`) apply to the calling process only (KeyPath.app). They cannot auto-enroll `kanata` in TCC.
- For `kanata`, we will guide the user in the wizard and verify via `PermissionOracle` (TCC read for kanata path). No background auto-prompt for `kanata` is attempted.

### Current Problem
- Users must manually navigate System Settings
- 7-step process: Click '+', navigate, add KeyPath, add kanata, enable checkboxes, restart
- Error-prone and frustrating

### Solution
Use `IOHIDRequestAccess()` and `AXIsProcessTrustedWithOptions()` to trigger automatic system permission dialogs.

### Implementation Details

#### 1.1 Create Permission Request Service

**File**: `Sources/KeyPath/Services/PermissionRequestService.swift`

```swift
import ApplicationServices
import IOKit.hid
import Foundation

@MainActor
class PermissionRequestService {
    static let shared = PermissionRequestService()
    
    private init() {}
    
    /// Request Input Monitoring permission using IOHIDRequestAccess()
    /// This automatically shows the system permission dialog
    func requestInputMonitoringPermission() -> Bool {
        AppLogger.shared.log("🔐 [PermissionRequest] Requesting Input Monitoring permission via IOHIDRequestAccess()")
        
        // IOHIDRequestAccess() automatically shows system dialog
        // Returns true if permission was already granted, false if user needs to approve
        let result = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        
        switch result {
        case kIOHIDAccessTypeGranted:
            AppLogger.shared.log("✅ [PermissionRequest] Input Monitoring already granted")
            return true
        case kIOHIDAccessTypeDenied:
            AppLogger.shared.log("❌ [PermissionRequest] Input Monitoring denied")
            return false
        default:
            // System dialog shown, user needs to approve
            AppLogger.shared.log("⏳ [PermissionRequest] Input Monitoring dialog shown - waiting for user approval")
            return false
        }
    }
    
    /// Request Accessibility permission using AXIsProcessTrustedWithOptions()
    /// This automatically shows the system permission dialog
    func requestAccessibilityPermission() -> Bool {
        AppLogger.shared.log("🔐 [PermissionRequest] Requesting Accessibility permission via AXIsProcessTrustedWithOptions()")
        
        // AXIsProcessTrustedWithOptions() with prompt option shows system dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        
        if result {
            AppLogger.shared.log("✅ [PermissionRequest] Accessibility already granted")
            return true
        } else {
            // System dialog shown, user needs to approve
            AppLogger.shared.log("⏳ [PermissionRequest] Accessibility dialog shown - waiting for user approval")
            return false
        }
    }
    
    /// Request both permissions (for wizard flow)
    func requestAllPermissions() async -> (inputMonitoring: Bool, accessibility: Bool) {
        let imResult = requestInputMonitoringPermission()
        
        // Small delay between requests to avoid overwhelming user
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let axResult = requestAccessibilityPermission()
        
        return (imResult, axResult)
    }
}
```

#### 1.1.1 Guardrails
- Foreground-only prompting: avoid hidden/behind-window system dialogs.
- Prompt cooldown (20 minutes default): avoid nagging if the user chooses “Later”.
- Small inter-prompt delay to avoid stacking dialogs.

#### 1.2 Update Wizard Pages to Use Automatic Prompts

**File**: `Sources/KeyPath/InstallationWizard/UI/Pages/WizardInputMonitoringPage.swift`

**Changes**:
- Replace `openInputMonitoringSettings()` with `PermissionRequestService.shared.requestInputMonitoringPermission()`
- Update button action to call automatic prompt
- Add polling logic to detect when permission is granted

**Key Changes**:
```swift
private func openInputMonitoringSettings() {
    AppLogger.shared.log("🔧 [WizardInputMonitoringPage] Requesting Input Monitoring permission")
    
    // Use automatic prompt instead of manual System Settings
    let alreadyGranted = PermissionRequestService.shared.requestInputMonitoringPermission()
    
    if alreadyGranted {
        // Permission already granted, refresh and continue
        Task {
            await onRefresh()
        }
    } else {
        // System dialog shown - start polling for permission grant
        startPermissionPolling(for: .inputMonitoring)
    }
}

private func startPermissionPolling(for type: CoordinatorPermissionType) {
    Task {
        var attempts = 0
        let maxAttempts = 30 // 30 seconds max
        
        while attempts < maxAttempts {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            attempts += 1
            
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            let hasPermission = switch type {
            case .inputMonitoring:
                snapshot.keyPath.inputMonitoring.isReady && snapshot.kanata.inputMonitoring.isReady
            case .accessibility:
                snapshot.keyPath.accessibility.isReady && snapshot.kanata.accessibility.isReady
            }
            
            if hasPermission {
                AppLogger.shared.log("✅ [WizardInputMonitoringPage] Permission granted!")
                await onRefresh()
                return
            }
        }
        
        AppLogger.shared.log("⏱️ [WizardInputMonitoringPage] Permission polling timeout")
    }
}
```

**File**: `Sources/KeyPath/InstallationWizard/UI/Pages/WizardAccessibilityPage.swift`

**Changes**: Same pattern as Input Monitoring page.

#### 1.3 Update Permission Grant Coordinator

**File**: `Sources/KeyPath/InstallationWizard/Core/PermissionGrantCoordinator.swift`

**Changes**:
- Add option to use automatic prompts instead of System Settings
- Keep System Settings as fallback for edge cases

#### 1.4 Handle Kanata Permission Requests

**Challenge**: `IOHIDRequestAccess()` and `AXIsProcessTrustedWithOptions()` only work for the calling process (KeyPath.app), not for kanata.

**Solution**: 
- Request permission for KeyPath.app automatically
- For kanata, still need to guide user to System Settings OR use a helper script
- Document that kanata permission may require manual approval (this is a macOS limitation)

**Alternative Approach**: Create a small helper tool that runs as kanata's user context to request permissions, but this adds complexity.

**Recommendation**: For Phase 1, request KeyPath.app permissions automatically, and provide clear instructions for kanata (which is less common to need manual approval anyway).

#### 1.5 Logging & Validation
- App logs: `~/Library/Logs/KeyPath/keypath-debug.log`
- Expected messages: Permission flow entry points (wizard pages), Oracle snapshots, banner visibility toggles.
- Unified log (optional): `log show --last 10m --predicate 'process == "KeyPath"'`

### Testing Plan

1. **Unit Tests**:
   - Test `PermissionRequestService` methods
   - Mock system APIs to verify correct calls
   - Test permission state detection

2. **Integration Tests**:
   - Test wizard flow with automatic prompts
   - Verify permission polling works correctly
   - Test fallback to System Settings if needed

3. **Manual Testing**:
   - Fresh install: Verify automatic prompts appear
   - Already granted: Verify no duplicate prompts
   - Denied: Verify fallback behavior

### Success Criteria

- ✅ One-click permission grant (vs. 7-step manual process)
- ✅ Automatic system dialogs appear
- ✅ Wizard detects permission grant without manual refresh
- ✅ Works for KeyPath.app permissions
- ✅ Clear instructions for kanata if manual approval needed

### Rollback Plan

- Feature flag: `useAutomaticPermissionPrompts` (default: `true`)
- If issues arise, can revert to manual System Settings flow
- No data migration needed

### Estimated Effort

- **Development**: 2-3 days
- **Testing**: 1 day
- **Total**: 3-4 days

---

## Phase 2: Just-in-Time Permission Requests (Best UX)

### Goal
Request permissions contextually when users actually try to use features that require them, rather than upfront during wizard.

### Current Problem
- Permissions requested upfront before user understands value
- Wizard blocks app usage until permissions granted
- Less contextual understanding of why permissions needed

### Solution
Detect when features requiring permissions are used, show contextual explanation, then request permission automatically.

### Implementation Details

#### 2.1 Create Permission Gate System

**File**: `Sources/KeyPath/Services/PermissionGate.swift`

```swift
import Foundation

/// Represents a feature that requires permissions
enum PermissionGatedFeature {
    case keyboardRemapping
    case emergencyStop
    case keyCapture
    case configurationReload
    
    var requiredPermissions: Set<PermissionType> {
        switch self {
        case .keyboardRemapping:
            return [.inputMonitoring, .accessibility]
        case .emergencyStop:
            return [.accessibility]
        case .keyCapture:
            return [.accessibility]
        case .configurationReload:
            return [.inputMonitoring]
        }
    }
    
    var contextualExplanation: String {
        switch self {
        case .keyboardRemapping:
            return "KeyPath needs permission to remap your keyboard keys. This allows you to customize your keyboard layout."
        case .emergencyStop:
            return "KeyPath needs Accessibility permission to detect the emergency stop sequence and keep you safe."
        case .keyCapture:
            return "KeyPath needs Accessibility permission to capture keyboard input for configuration."
        case .configurationReload:
            return "KeyPath needs Input Monitoring permission to apply keyboard remapping changes."
        }
    }
}

@MainActor
class PermissionGate {
    static let shared = PermissionGate()
    
    private let permissionService = PermissionRequestService.shared
    private let oracle = PermissionOracle.shared
    
    private init() {}
    
    /// Check if feature can be used, request permissions if needed
    func checkAndRequestPermissions(
        for feature: PermissionGatedFeature,
        onGranted: @escaping () async -> Void,
        onDenied: @escaping () -> Void
    ) async {
        let snapshot = await oracle.currentSnapshot()
        
        // Check if all required permissions are granted
        let missingPermissions = feature.requiredPermissions.filter { permissionType in
            switch permissionType {
            case .inputMonitoring:
                return !snapshot.keyPath.inputMonitoring.isReady || !snapshot.kanata.inputMonitoring.isReady
            case .accessibility:
                return !snapshot.keyPath.accessibility.isReady || !snapshot.kanata.accessibility.isReady
            }
        }
        
        if missingPermissions.isEmpty {
            // All permissions granted, proceed
            await onGranted()
            return
        }
        
        // Show contextual explanation dialog
        let userApproved = await showPermissionRequestDialog(
            feature: feature,
            missingPermissions: missingPermissions
        )
        
        if !userApproved {
            onDenied()
            return
        }
        
        // Request permissions automatically
        await requestMissingPermissions(missingPermissions)
        
        // Poll for permission grant
        let granted = await pollForPermissions(missingPermissions, maxAttempts: 30)
        
        if granted {
            await onGranted()
        } else {
            onDenied()
        }
    }
    
    private func showPermissionRequestDialog(
        feature: PermissionGatedFeature,
        missingPermissions: Set<PermissionType>
    ) async -> Bool {
        // Show NSAlert with contextual explanation
        // Return true if user clicks "Allow", false if "Cancel"
        // Implementation details in UI layer
        return await PermissionRequestDialog.show(
            explanation: feature.contextualExplanation,
            permissions: missingPermissions
        )
    }
    
    private func requestMissingPermissions(_ permissions: Set<PermissionType>) async {
        for permission in permissions {
            switch permission {
            case .inputMonitoring:
                _ = permissionService.requestInputMonitoringPermission()
            case .accessibility:
                _ = permissionService.requestAccessibilityPermission()
            }
            // Small delay between requests
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    private func pollForPermissions(_ permissions: Set<PermissionType>, maxAttempts: Int) async -> Bool {
        for _ in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            let snapshot = await oracle.currentSnapshot()
            let allGranted = permissions.allSatisfy { permissionType in
                switch permissionType {
                case .inputMonitoring:
                    return snapshot.keyPath.inputMonitoring.isReady && snapshot.kanata.inputMonitoring.isReady
                case .accessibility:
                    return snapshot.keyPath.accessibility.isReady && snapshot.kanata.accessibility.isReady
                }
            }
            
            if allGranted {
                return true
            }
        }
        return false
    }
}
```

#### 2.2 Integrate Permission Gates into Feature Code

**File**: `Sources/KeyPath/Services/KeyboardCapture.swift`

**Changes**: Wrap `startCapture()` with permission gate:

```swift
func startCapture(callback: @escaping (String) -> Void) {
    guard !isCapturing else { return }
    
    Task { @MainActor in
        await PermissionGate.shared.checkAndRequestPermissions(
            for: .keyCapture,
            onGranted: {
                // Original capture logic here
                self.captureCallback = callback
                self.isCapturing = true
                // ... rest of capture setup
            },
            onDenied: {
                callback("⚠️ Permission required for keyboard capture")
            }
        )
    }
}
```

**File**: `Sources/KeyPath/Managers/KanataManager.swift`

**Changes**: Wrap configuration reload with permission gate:

```swift
func reloadConfiguration() async throws {
    await PermissionGate.shared.checkAndRequestPermissions(
        for: .configurationReload,
        onGranted: {
            // Original reload logic
        },
        onDenied: {
            throw KeyPathError.permission(.missingRequiredPermission)
        }
    )
}
```

**File**: `Sources/KeyPath/UI/EmergencyStopPauseCard.swift`

**Changes**: Wrap emergency stop detection with permission gate (if not already granted).

#### 2.3 Create Permission Request Dialog UI

**File**: `Sources/KeyPath/UI/PermissionRequestDialog.swift`

```swift
import SwiftUI

struct PermissionRequestDialog: View {
    let explanation: String
    let permissions: Set<PermissionType>
    @Binding var isPresented: Bool
    let onAllow: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Permission Required")
                .font(.headline)
            
            Text(explanation)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Cancel") {
                    onCancel()
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Allow") {
                    onAllow()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    static func show(
        explanation: String,
        permissions: Set<PermissionType>
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            // Show dialog and wait for user response
            // Implementation uses NSAlert or SwiftUI sheet
        }
    }
}
```

#### 2.4 Update Wizard to Support "Skip" Option

**File**: `Sources/KeyPath/InstallationWizard/UI/InstallationWizardView.swift`

**Changes**:
- Add "Skip Setup" button to wizard
- Allow wizard to be dismissed without permissions
- Document that permissions will be requested just-in-time

### Testing Plan

1. **Unit Tests**:
   - Test `PermissionGate` logic
   - Test permission detection
   - Test contextual explanations

2. **Integration Tests**:
   - Test feature gating (keyboard remapping, emergency stop, etc.)
   - Test permission request flow
   - Test fallback behavior

3. **Manual Testing**:
   - Try to use feature without permission → verify dialog appears
   - Grant permission → verify feature works immediately
   - Deny permission → verify graceful degradation
   - Skip wizard → verify just-in-time requests work

### Success Criteria

- ✅ Permissions requested contextually when features used
- ✅ Clear explanations of why permissions needed
- ✅ Features work immediately after permission grant
- ✅ Wizard can be skipped
- ✅ Graceful degradation if permissions denied

### Rollback Plan

- Feature flag: `useJustInTimePermissionRequests` (default: `false` initially)
- Can revert to Phase 1 (automatic prompts in wizard) if issues arise
- No data migration needed

### Estimated Effort

- **Development**: 4-5 days
- **Testing**: 2 days
- **Total**: 6-7 days

---

## Phase 3: Optional Wizard (Complete Modern Experience)

### Goal
Make the installation wizard optional, allowing the app to launch and be used without requiring upfront permission setup.

### Current Problem
- Wizard blocks app usage until permissions granted
- Users can't explore app before granting permissions
- Setup feels mandatory rather than helpful

### Solution
Allow app to launch without permissions, show clear indicators of what's disabled, make wizard optional "Complete Setup" flow.

### Implementation Details

#### 3.1 Update App Launch Logic

**File**: `Sources/KeyPath/App.swift`

**Changes**:
- Don't force wizard on launch if permissions missing
- Check permissions on launch, but don't block
- Show "Complete Setup" banner if permissions missing

**Key Changes**:
```swift
@main
struct KeyPathApp: App {
    @StateObject private var kanataManager = KanataManager()
    @State private var showWizard = false
    @State private var showSetupBanner = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(kanataManager)
                .onAppear {
                    checkInitialPermissions()
                }
                .sheet(isPresented: $showWizard) {
                    InstallationWizardView(...)
                }
                .overlay(alignment: .top) {
                    if showSetupBanner {
                        SetupBanner(onCompleteSetup: {
                            showWizard = true
                        })
                    }
                }
        }
    }
    
    private func checkInitialPermissions() {
        Task {
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            if !snapshot.isSystemReady {
                // Show banner, but don't force wizard
                showSetupBanner = true
            }
        }
    }
}
```

#### 3.2 Create Setup Banner Component

**File**: `Sources/KeyPath/UI/SetupBanner.swift`

```swift
import SwiftUI

struct SetupBanner: View {
    let onCompleteSetup: () -> Void
    @State private var isDismissed = false
    
    var body: some View {
        if !isDismissed {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Complete Setup")
                            .font(.headline)
                        Text("Grant permissions to enable keyboard remapping")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Complete Setup") {
                        onCompleteSetup()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button {
                        isDismissed = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
            .transition(.move(edge: .top))
        }
    }
}
```

#### 3.3 Update Main UI to Show Permission Status

**File**: `Sources/KeyPath/UI/ContentView.swift`

**Changes**:
- Show indicators for disabled features
- Add "Complete Setup" button in settings
- Show permission status in status bar/menu

**Key Changes**:
```swift
struct ContentView: View {
    @EnvironmentObject var kanataManager: KanataManager
    @State private var permissionStatus: PermissionStatus = .checking
    
    var body: some View {
        VStack {
            // Main content
            
            if permissionStatus == .missing {
                PermissionStatusCard {
                    // Show what's disabled
                    // Offer "Complete Setup" button
                }
            }
        }
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        Task {
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            permissionStatus = snapshot.isSystemReady ? .granted : .missing
        }
    }
}
```

#### 3.4 Update Wizard to be Non-Blocking

**File**: `Sources/KeyPath/InstallationWizard/UI/InstallationWizardView.swift`

**Changes**:
- Add "Skip" button on first page
- Allow wizard to be closed without completing
- Save wizard state so it can be resumed later
- Don't block app functionality if wizard skipped

#### 3.5 Add Permission Status Indicators

**File**: `Sources/KeyPath/UI/PermissionStatusCard.swift`

```swift
import SwiftUI

struct PermissionStatusCard: View {
    let onCompleteSetup: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                
                Text("Some features require permissions")
                    .font(.headline)
                
                Spacer()
                
                Button("Complete Setup") {
                    onCompleteSetup()
                }
                .buttonStyle(.borderedProminent)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                PermissionRequirementRow(
                    icon: "keyboard",
                    feature: "Keyboard Remapping",
                    status: .missing
                )
                PermissionRequirementRow(
                    icon: "exclamationmark.triangle",
                    feature: "Emergency Stop",
                    status: .missing
                )
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct PermissionRequirementRow: View {
    let icon: String
    let feature: String
    let status: PermissionStatus
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(feature)
                .font(.subheadline)
            Spacer()
            if status == .missing {
                Text("Requires permission")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

#### 3.6 Update Settings to Show Setup Option

**File**: `Sources/KeyPath/UI/SettingsView.swift`

**Changes**:
- Add "Complete Setup" section if permissions missing
- Show current permission status
- Link to wizard

### Testing Plan

1. **Unit Tests**:
   - Test app launch without permissions
   - Test setup banner display logic
   - Test permission status detection

2. **Integration Tests**:
   - Test wizard skip functionality
   - Test just-in-time requests after skip
   - Test setup banner dismissal

3. **Manual Testing**:
   - Launch app without permissions → verify app launches
   - Verify setup banner appears
   - Skip wizard → verify just-in-time requests work
   - Complete wizard → verify permissions granted
   - Test all combinations of permission states

### Success Criteria

- ✅ App launches without blocking wizard
- ✅ Setup banner appears if permissions missing
- ✅ Wizard can be skipped
- ✅ Just-in-time requests work after skip
- ✅ Clear indicators of disabled features
- ✅ "Complete Setup" easily accessible

### Rollback Plan

- Feature flag: `allowOptionalWizard` (default: `false` initially)
- Can revert to Phase 2 (just-in-time but wizard still blocks) if issues arise
- No data migration needed

### Estimated Effort

- **Development**: 3-4 days
- **Testing**: 2 days
- **Total**: 5-6 days

---

## Overall Implementation Strategy

### Phased Rollout

1. **Phase 1** (Week 1): Automatic prompts
   - Low risk, high impact
   - Immediate UX improvement
   - Can ship independently

2. **Phase 2** (Week 2-3): Just-in-time requests
   - Medium risk, very high impact
   - Requires Phase 1 complete
   - More complex but better UX

3. **Phase 3** (Week 4): Optional wizard
   - Low risk, high impact
   - Requires Phase 2 complete
   - Completes modern UX transformation

### Feature Flags

- `useAutomaticPermissionPrompts` (Phase 1)
- `useJustInTimePermissionRequests` (Phase 2)
- `allowOptionalWizard` (Phase 3)

All flags default to `false` initially, enabled after testing.

### Testing Strategy

- **Unit tests** for each phase
- **Integration tests** for permission flows
- **Manual testing** with fresh installs
- **Beta testing** before full rollout

### Success Metrics

- **Phase 1**: Reduction in support tickets about permission setup
- **Phase 2**: Increase in permission grant rate
- **Phase 3**: Increase in app usage without wizard completion

### Risks and Mitigations

1. **Risk**: Automatic prompts may not work in all scenarios
   - **Mitigation**: Fallback to System Settings, extensive testing

2. **Risk**: Just-in-time requests may interrupt workflow
   - **Mitigation**: Clear explanations, contextual timing

3. **Risk**: Optional wizard may confuse users
   - **Mitigation**: Clear setup banner, easy access to wizard

### Dependencies

- **Phase 1**: No dependencies
- **Phase 2**: Requires Phase 1
- **Phase 3**: Requires Phase 2

### Timeline

- **Phase 1**: 1 week (3-4 days dev + 1 day testing)
- **Phase 2**: 1-2 weeks (6-7 days dev + 2 days testing)
- **Phase 3**: 1 week (5-6 days dev + 2 days testing)
- **Total**: 3-4 weeks

---

## Conclusion

This three-phase plan transforms KeyPath's permission handling from a manual, frustrating process to a modern, contextual, user-friendly experience that matches Apple's recommendations and best practices from cutting-edge Mac apps.

Each phase builds on the previous one, allowing for incremental rollout and risk mitigation. The plan balances immediate improvements (Phase 1) with long-term UX excellence (Phases 2-3).

