# Mac-Native Keyboard Shortcuts & Button Order Fix

## Goal
Add standard macOS keyboard shortcuts and ensure button order follows HIG. This is a **small, high-impact** improvement (~2-3 hours).

## Current State

### Existing Keyboard Shortcuts ✅
- `Cmd+O` - Open Config
- `Cmd+Shift+N` - Show Installation Wizard  
- `Cmd+Shift+E` - Emergency Stop Help

### Missing Standard Shortcuts ❌
- `Cmd+,` - Open Settings (SwiftUI Settings scene handles this automatically, but menu item missing)
- `Cmd+W` - Close Window (standard macOS)
- `Cmd+H` - Hide KeyPath (standard macOS)
- `Cmd+Q` - Quit KeyPath (standard macOS)
- `Cmd+M` - Minimize Window (standard macOS, optional)

### Button Order Status
- Most AppKit alerts: ✅ Already correct (primary right, Cancel left)
- SwiftUI alerts: ⚠️ Needs verification

## Implementation Plan

### Phase 1: Add Standard Menu Shortcuts (30 minutes)

**Files to Modify**: `Sources/KeyPath/App.swift`

**Tasks**:
1. Add standard keyboard shortcuts to menu:
   - `Cmd+,` - Settings (verify it works with SwiftUI Settings scene)
   - `Cmd+W` - Close Window
   - `Cmd+H` - Hide
   - `Cmd+Q` - Quit
   - `Cmd+M` - Minimize (optional)

2. Add proper menu structure:
   - Ensure "KeyPath" menu has About, Settings, Hide, Quit
   - Ensure Window menu has Minimize, Close, etc.

**Implementation**:
```swift
.commands {
    // KeyPath menu
    CommandGroup(replacing: .appInfo) {
        Button("About KeyPath") { ... }
        Divider()
        Button("Settings...") {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
    
    // Window menu
    CommandGroup(replacing: .windowArrangement) {
        Button("Minimize") {
            NSApp.keyWindow?.miniaturize(nil)
        }
        .keyboardShortcut("m", modifiers: .command)
        
        Button("Close") {
            NSApp.keyWindow?.close()
        }
        .keyboardShortcut("w", modifiers: .command)
    }
    
    // Hide/Quit
    CommandGroup(replacing: .appTermination) {
        Button("Hide KeyPath") {
            NSApp.hide(nil)
        }
        .keyboardShortcut("h", modifiers: .command)
        
        Divider()
        
        Button("Quit KeyPath") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
    
    // Keep existing File menu items
    CommandGroup(replacing: .newItem) {
        // ... existing Open Config, Wizard, etc.
    }
}
```

**Testing**:
- Test Cmd+, opens Settings
- Test Cmd+W closes active window
- Test Cmd+H hides app
- Test Cmd+Q quits app
- Verify shortcuts don't conflict

---

### Phase 2: Button Order Audit & Quick Fixes (1-2 hours)

**Goal**: Verify and fix button order in SwiftUI alerts

**Files to Review**:

1. **ContentView.swift** (5 alerts)
   - Line 299-307: "Emergency Stop Activated" (OK only) ✅
   - Line 319-326: "Kanata Installation Required" 
     - Current: "Open Wizard" (first), "Cancel" (second)
     - ✅ Correct: Primary action right, Cancel left
   - Line 327-335: "Configuration Issue Detected"
     - Current: "OK" (first), "View Diagnostics" (second)
     - ⚠️ Check: Should "View Diagnostics" be primary?
   - Line 336-348: "Configuration Repair Failed"
     - Current: "OK", "Open Failed Config in Zed", "View Diagnostics"
     - ⚠️ Check: Multiple actions - order needs review
   - Line 349-355: "Kanata Not Running"
     - Current: "OK" (first), "Open Wizard" (second)
     - ✅ Correct: Primary action right, Cancel left

2. **SettingsView.swift** (5 alerts)
   - Line 875: "Reset Configuration?"
     - Current: "Cancel", "Reset" (destructive)
     - ✅ Correct: Cancel left, Destructive right
   - Line 885: "Change TCP Port"
     - Current: "Cancel", "Apply"
     - ✅ Correct: Cancel left, Primary right

3. **InstallationWizardView.swift** (1 alert)
   - Line 116-130: "Close Setup Wizard?"
     - Current: "Cancel", "Close Anyway" (destructive)
     - ✅ Correct: Cancel left, Destructive right

**Action Items**:
- Review each alert visually
- Fix any button order issues
- Ensure button roles are correct (.cancel, .destructive)
- Verify Return/Escape key behavior

**Button Order Rules**:
- ✅ Cancel: Leftmost, `.cancel` role
- ✅ Primary: Rightmost, default (Return key)
- ✅ Destructive: Primary position, `.destructive` role
- ✅ Multiple actions: Primary right, secondary left, Cancel leftmost

**Files to Modify**:
- `Sources/KeyPath/UI/ContentView.swift` - Fix button order if needed
- `Sources/KeyPath/UI/SettingsView.swift` - Verify button order
- `Sources/KeyPath/InstallationWizard/UI/InstallationWizardView.swift` - Verify button order

**Testing**:
- Visual inspection of all dialogs
- Test Return key triggers primary action
- Test Escape key triggers Cancel
- Verify button roles work correctly

---

### Phase 3: Terminology Polish (30 minutes)

**Goal**: Quick pass to ensure button labels follow HIG conventions

**HIG Button Label Rules**:
- ✅ Use action verbs: "Open", "Save", "Delete"
- ✅ "Cancel" not "Close" or "No"
- ✅ "OK" for informational only
- ❌ Avoid "Yes"/"No" - prefer descriptive actions

**Files to Review**:
- All alert dialogs
- All button labels

**Action Items**:
- Replace any "Yes"/"No" with descriptive actions
- Ensure "Cancel" is used consistently
- Verify button labels are clear and action-oriented

---

## Implementation Order

1. **Phase 1** - Add keyboard shortcuts (30 min) - **Highest impact**
2. **Phase 2** - Button order audit (1-2 hours) - **Visual polish**
3. **Phase 3** - Terminology polish (30 min) - **Quick cleanup**

**Total Time**: ~2-3 hours

## Success Criteria

✅ Cmd+, opens Settings
✅ Cmd+W closes window
✅ Cmd+H hides app
✅ Cmd+Q quits app
✅ All alerts have correct button order
✅ Button labels follow HIG conventions
✅ Keyboard shortcuts work as expected
✅ No regressions

## Notes

- SwiftUI Settings scene may already handle Cmd+, automatically - verify first
- Window management shortcuts may need AppDelegate coordination
- Button order in SwiftUI alerts uses button order in code (first = leftmost)
- Test all shortcuts to ensure no conflicts with existing functionality
