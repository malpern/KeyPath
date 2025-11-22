# Alert Sheet Migration Plan

## Goal
Convert all app-modal alerts and permission dialogs to window-attached sheets following macOS Human Interface Guidelines, with correct button order and keyboard shortcuts.

## Current State Analysis

### AppKit NSAlert with `runModal()` (App-Modal, Blocking)
1. **KarabinerConflictService.swift** (line 307-320)
   - "Disable Karabiner Elements?" dialog
   - Button order: ✅ Correct (Primary right, Cancel left)
   - Issue: App-modal blocking

2. **PermissionGrantCoordinator.swift** (line 90-97)
   - Permission instruction dialogs
   - Button order: ✅ Correct (Primary right, Cancel left)
   - Issue: App-modal blocking

3. **WizardAutoFixer.swift** (multiple locations)
   - Line 292-300: "Karabiner Driver Version Fix Required"
   - Line 335-348: "Driver Version Fixed" (OK only)
   - Line 355-360: "Installation Failed" (OK only)
   - Line 785-806: "Driver Extension Activation Required"
   - Button order: ✅ Mostly correct
   - Issue: App-modal blocking

4. **KanataManager.swift** (line 691-701)
   - "Safety Timeout Activated" (OK only)
   - Button order: ✅ Correct (OK only)
   - Issue: App-modal blocking

### SwiftUI `.alert()` Modifiers (App-Modal)
1. **ContentView.swift**
   - Line 299-307: "Emergency Stop Activated" (OK only)
   - Line 319-326: "Kanata Installation Required" (Open Wizard, Cancel)
   - Line 327-335: "Configuration Issue Detected" (OK, View Diagnostics)
   - Line 336-348: "Configuration Repair Failed" (OK, Open in Zed, View Diagnostics)
   - Line 349-355: "Kanata Not Running" (OK, Open Wizard)
   - Button order: ⚠️ Mixed - some need reordering
   - Issue: App-modal

2. **SettingsView.swift**
   - Line 127: "Reset Configuration?" confirmation
   - Line 135: "Developer Reset" confirmation
   - Line 453: "Uninstall Privileged Helper?" confirmation
   - Line 875: "Reset Configuration" confirmation
   - Line 885: "Change TCP Port" input
   - Button order: ⚠️ Needs verification
   - Issue: App-modal

3. **InstallationWizardView.swift**
   - Line 116-130: "Close Setup Wizard?" confirmation
   - Button order: ⚠️ Cancel left, Destructive right - needs review
   - Issue: App-modal

   - Line 71: "Launch Agent Error" alert
   - Button order: Unknown
   - Issue: App-modal

### Window Structure
- **Main Window**: Managed by `MainWindowController` (App.swift line 296)
- **Settings Window**: SwiftUI Settings scene (App.swift line 74)
- **Wizard Window**: Separate window for installation wizard

## Implementation Plan

### Phase 1: Create Window Access Utilities
**Goal**: Provide reliable way to get current window for sheet attachment

**Tasks**:
1. Create `WindowAccessor.swift` utility with:
   - `func currentWindow() -> NSWindow?` - Gets frontmost window
   - `func mainWindow() -> NSWindow?` - Gets main application window
   - `func settingsWindow() -> NSWindow?` - Gets settings window (if open)
   - Handle edge cases (headless mode, no windows, etc.)

**Files to Create**:
- `Sources/KeyPath/UI/Utilities/WindowAccessor.swift`

**Testing**:
- Test in headless mode (should return nil gracefully)
- Test when no windows are visible
- Test when multiple windows are open

---

### Phase 2: Create NSAlert Sheet Helper
**Goal**: Convert AppKit `runModal()` calls to `beginSheetModal(for:)`

**Tasks**:
1. Create `AlertSheetHelper.swift` with:
   - `func showAlertSheet(window: NSWindow?, alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void)`
   - Handles nil window gracefully (falls back to app-modal)
   - Ensures correct button order (primary right, Cancel left)
   - Sets up keyboard shortcuts (Return for primary, Escape for Cancel)

**Files to Create**:
- `Sources/KeyPath/UI/Utilities/AlertSheetHelper.swift`

**Button Order Rules**:
- Primary action button: Rightmost position
- Cancel button: Leftmost position (if present)
- Destructive actions: Red text, primary position
- OK-only alerts: Single button, right-aligned

**Keyboard Shortcuts**:
- Return/Enter: Triggers primary action button
- Escape: Triggers Cancel button (if present)
- Tab: Navigate between buttons
- Space: Activate focused button

**Testing**:
- Test with nil window (fallback behavior)
- Test button order
- Test keyboard shortcuts
- Test with test environment flag (should skip)

---

### Phase 3: Convert AppKit NSAlert Dialogs
**Goal**: Replace all `runModal()` calls with sheet-based presentation

**Files to Modify**:

1. **KarabinerConflictService.swift** (line 300-325)
   - Replace `runModal()` with `AlertSheetHelper.showAlertSheet()`
   - Get window from `WindowAccessor.mainWindow()`
   - Maintain async continuation pattern

2. **PermissionGrantCoordinator.swift** (line 81-102)
   - Replace `runModal()` with `AlertSheetHelper.showAlertSheet()`
   - Get window from `WindowAccessor.mainWindow()`
   - Convert to async/await pattern

3. **WizardAutoFixer.swift** (4 locations)
   - Line 292-300: Driver version fix dialog
   - Line 335-348: Success dialog
   - Line 355-360: Failure dialog
   - Line 785-806: Activation required dialog
   - Replace all `runModal()` calls
   - Get window from `WindowAccessor.mainWindow()`

4. **KanataManager.swift** (line 686-703)
   - Replace `runModal()` with `AlertSheetHelper.showAlertSheet()`
   - Get window from `WindowAccessor.mainWindow()`

**Testing**:
- Test each dialog individually
- Verify button order
- Verify keyboard shortcuts
- Test in test environment (should skip)
- Test window attachment (verify sheet appears attached to window)

---

### Phase 4: Convert SwiftUI Alert Modifiers
**Goal**: Replace `.alert()` modifiers with `.sheet()` or AppKit sheet integration

**Decision**: Use AppKit sheets for SwiftUI alerts when:
- Dialog is triggered from background/async code
- Need precise control over button order
- Window attachment is critical

Use SwiftUI `.confirmationDialog()` or `.sheet()` when:
- Dialog is triggered from within SwiftUI view hierarchy
- Can use SwiftUI's built-in sheet presentation

**Files to Modify**:

1. **ContentView.swift** (5 alerts)
   - **Emergency Stop**: Convert to AppKit sheet (triggered from background)
   - **Installation Required**: Convert to AppKit sheet (triggered from manager)
   - **Config Issue**: Convert to AppKit sheet (triggered from manager)
   - **Config Repair Failed**: Convert to AppKit sheet (triggered from manager)
   - **Kanata Not Running**: Convert to AppKit sheet (triggered from manager)
   - Remove `@State` alert flags
   - Use `AlertSheetHelper` in callback handlers

2. **SettingsView.swift** (5 alerts)
   - **Reset Configuration**: Use SwiftUI `.confirmationDialog()` (user-initiated)
   - **Developer Reset**: Use SwiftUI `.confirmationDialog()`
   - **Uninstall Helper**: Use SwiftUI `.confirmationDialog()`
   - **Change TCP Port**: Use SwiftUI `.sheet()` with custom input view
   - Verify button order matches HIG

3. **InstallationWizardView.swift** (1 alert)
   - **Close Wizard**: Use SwiftUI `.confirmationDialog()` (user-initiated)
   - Fix button order: Cancel left, Destructive right

4. **LaunchAgentSettingsView.swift** (removed in strangler cleanup)
   - **Launch Agent Error**: Convert to AppKit sheet (error condition)
   - Use `AlertSheetHelper`

**Testing**:
- Test each converted alert
- Verify sheet appears attached to correct window
- Test button order
- Test keyboard shortcuts
- Test dismiss behavior

---

### Phase 5: Create SwiftUI Sheet Helper (Optional)
**Goal**: Provide reusable SwiftUI component for AppKit-style alert sheets

**Tasks**:
1. Create `AlertSheetModifier.swift` ViewModifier
   - Wraps AppKit sheet presentation
   - Provides SwiftUI-friendly API
   - Handles window access automatically

**Files to Create**:
- `Sources/KeyPath/UI/Modifiers/AlertSheetModifier.swift`

**Usage Example**:
```swift
.alertSheet(
    isPresented: $showingAlert,
    title: "Alert Title",
    message: "Alert message",
    primaryButton: ("Confirm", .default),
    secondaryButton: ("Cancel", .cancel)
) { response in
    // Handle response
}
```

**Testing**:
- Test modifier attachment
- Test state management
- Test multiple alerts

---

### Phase 6: Button Order Verification & Fixes
**Goal**: Ensure all dialogs follow HIG button order

**HIG Rules**:
1. **Primary action**: Rightmost button, default (Return key)
2. **Cancel**: Leftmost button, Cancel role (Escape key)
3. **Destructive**: Primary position, destructive style (red text)
4. **Multiple actions**: Primary right, secondary left, Cancel leftmost

**Files to Review**:
- All converted alerts
- All SwiftUI confirmation dialogs
- Verify button titles match HIG conventions

**Button Title Conventions**:
- ✅ "Open System Settings" (action verb)
- ✅ "Cancel" (not "Close" or "No")
- ✅ "OK" (for informational only)
- ✅ "Disable Conflicting Services" (descriptive action)
- ❌ "Yes" / "No" (prefer descriptive actions)

**Testing**:
- Visual inspection of all dialogs
- Keyboard shortcut testing
- Screen reader testing (accessibility)

---

### Phase 7: Keyboard Shortcut Implementation
**Goal**: Ensure Return/Escape work correctly for all sheets

**Implementation**:
- NSAlert automatically handles Return/Escape for buttons
- For SwiftUI dialogs, ensure `.keyboardShortcut()` modifiers are applied
- Test accessibility keyboard navigation

**Testing**:
- Test Return key triggers primary action
- Test Escape key triggers Cancel
- Test Tab navigation between buttons
- Test with VoiceOver enabled

---

### Phase 8: Testing & Validation
**Goal**: Comprehensive testing of all converted dialogs

**Test Scenarios**:

1. **Window States**:
   - Main window visible
   - Main window minimized
   - Main window hidden
   - Settings window open
   - Wizard window open
   - No windows visible (headless mode)

2. **Alert Types**:
   - Informational (OK only)
   - Confirmation (OK/Cancel)
   - Multiple actions (3+ buttons)
   - Destructive actions

3. **Interaction Methods**:
   - Mouse click
   - Keyboard shortcuts (Return, Escape)
   - Tab navigation
   - VoiceOver navigation

4. **Edge Cases**:
   - Rapid dismissal
   - Multiple alerts queued
   - Alert during window transition
   - Test environment (should skip)

**Test Files to Create**:
- `Tests/KeyPathTests/AlertSheetTests.swift`

**Manual Testing Checklist**:
- [ ] All AppKit alerts appear as sheets
- [ ] All SwiftUI alerts converted appropriately
- [ ] Button order follows HIG
- [ ] Keyboard shortcuts work
- [ ] Sheets attach to correct window
- [ ] Sheets dismiss correctly
- [ ] No regressions in functionality
- [ ] Test environment still works

---

### Phase 9: Documentation Updates
**Goal**: Update code documentation and guides

**Files to Update**:
- `ARCHITECTURE.md` - Document alert sheet pattern
- `docs/NEW_DEVELOPER_GUIDE.md` - Add alert sheet guidelines
- Code comments - Document button order decisions

**Documentation to Add**:
- When to use AppKit sheets vs SwiftUI dialogs
- Button order conventions
- Keyboard shortcut standards
- Window access patterns

---

## Implementation Order

1. **Phase 1** - Window Access Utilities (Foundation)
2. **Phase 2** - Alert Sheet Helper (Foundation)
3. **Phase 3** - Convert AppKit NSAlert (Low risk, high impact)
4. **Phase 6** - Button Order Verification (Can parallel with Phase 3)
5. **Phase 4** - Convert SwiftUI Alerts (Higher risk, requires testing)
6. **Phase 5** - SwiftUI Sheet Helper (Optional optimization)
7. **Phase 7** - Keyboard Shortcuts (Polish)
8. **Phase 8** - Testing & Validation (Critical)
9. **Phase 9** - Documentation (Final)

## Risk Assessment

**Low Risk**:
- Creating utility files (Phase 1, 2)
- Converting AppKit alerts (Phase 3)
- Button order fixes (Phase 6)

**Medium Risk**:
- Converting SwiftUI alerts (Phase 4)
- Window access edge cases

**High Risk Areas**:
- Permission dialogs (critical path)
- Wizard dialogs (user-facing)
- Error dialogs (must work correctly)

**Mitigation**:
- Incremental changes
- Comprehensive testing
- Fallback to app-modal if window unavailable
- Test environment compatibility

## Success Criteria

✅ All alerts appear as window-attached sheets
✅ Primary action button on right
✅ Cancel button on left (when present)
✅ Return key triggers primary action
✅ Escape key triggers Cancel
✅ Sheets attach to correct window
✅ No app-modal blocking dialogs remain
✅ Test environment still works
✅ No regressions in functionality

## Estimated Effort

- Phase 1: 2-3 hours
- Phase 2: 3-4 hours
- Phase 3: 4-6 hours
- Phase 4: 6-8 hours
- Phase 5: 2-3 hours (optional)
- Phase 6: 2-3 hours
- Phase 7: 1-2 hours
- Phase 8: 4-6 hours
- Phase 9: 1-2 hours

**Total**: ~25-35 hours

## Notes

- Maintain test environment compatibility (skip alerts in tests)
- Some alerts may need to remain app-modal if no window is available
- Consider user experience: sheets feel more native but may be less intrusive
- Document any intentional deviations from HIG
