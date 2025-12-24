# Missing Accessibility Identifiers

**Generated:** December 24, 2025  
**Total Missing:** ~100+ interactive elements

## Priority Classification

### 🔴 High Priority (User-Facing, Core Features)

#### Diagnostic Views
- `DiagnosticSummarySection.swift`
  - "View Details" button (line 22)
  - "Fix" buttons (line 40) - Multiple instances per diagnostic
- `DiagnosticSummaryView.swift`
  - "View Details" button (line 29)

#### Emergency Stop
- `EmergencyStopPauseCard.swift`
  - "Restart Service" button (line 39)

#### Active Rules View
- `ActiveRulesView.swift`
  - "Edit Config" button (line 18)
  - Rule collection toggle (line 83)
  - Expand/collapse button (line 94)

#### Overlay Inspector Content
- `LiveKeyboardOverlayView.swift`
  - Include punctuation toggle (line 604)
  - Keymap selection buttons (line 674)
  - Layout selection buttons (line 757)
  - Colorway selection buttons (line 832)
  - Toolbar buttons (line 945)
- `KeyboardSelectionGridView.swift`
  - Layout selection buttons (line 50)
- `TypingSoundsSection.swift`
  - Sound selection buttons (line 80)

### 🟡 Medium Priority (Less Common, Still Important)

#### Content View
- `ContentView.swift`
  - Alert "Dismiss" button (line 546)

#### Installer View
- `InstallerView.swift`
  - "Done" button (line 37)

#### Mapper View (Experimental)
- `MapperView.swift`
  - Some action buttons (line 356)
- `MapperWindowController.swift`
  - "Cancel" button (line 129)
  - "OK" button (line 134)

### 🟢 Low Priority (Experimental/System)

#### Experimental Views
- `InputCaptureExperiment.swift`
  - Clear button (line 101)
  - Done button (line 262)
  - Delete buttons (line 336)

#### System Dialogs
- `PermissionRequestDialog.swift`
  - NSAlert buttons (lines 16-17) - System-managed, may not need identifiers

## Implementation Plan

### Phase 1: High Priority (Immediate)
1. Diagnostic views (3 files)
2. Emergency stop pause card
3. Active rules view
4. Overlay inspector content

### Phase 2: Medium Priority (Next Sprint)
1. Content view alerts
2. Installer view
3. Mapper view remaining

### Phase 3: Low Priority (Future)
1. Experimental views
2. System dialogs (if needed)

## Notes

- **System Dialogs**: NSAlert buttons may not support SwiftUI accessibility identifiers. May need to use NSButton accessibility APIs instead.
- **Experimental Views**: Consider removing or stabilizing before adding identifiers.
- **Dynamic Content**: Some buttons are in ForEach loops - need dynamic identifiers based on item ID.
