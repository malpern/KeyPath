# KeyPath Accessibility Coverage

**Last Updated:** December 24, 2025  
**Total Accessibility Identifiers:** 50+ across all major UI screens

## Overview

KeyPath now has comprehensive accessibility identifiers across all major screens, enabling full automation via tools like Peekaboo, XCUITest, and other accessibility-based automation frameworks.

## Coverage by Screen

### ✅ Main Popover (ContentView)

| Element | Identifier | Label |
|---------|------------|-------|
| Launch Wizard Button | `launch-installation-wizard-button` | Launch Installation Wizard |
| System Status Indicator | `system-status-indicator` | System status good/warning/critical |
| Input Recording Section | `input-recording-section` | Input key recording section |
| Input Key Display | `input-key-display` | Input key |
| Input Record Button | `input-key-record-button` | Start recording input key |
| Output Recording Section | `output-recording-section` | Output key recording section |
| Output Key Display | `output-key-display` | Output key |
| Output Record Button | `output-key-record-button` | Start recording output key |
| Save Button | `save-mapping-button` | Save key mapping |
| Validation Copy Errors | `validation-copy-errors-button` | Copy Errors |
| Validation Open Config | `validation-open-config-button` | Open Config in Zed |
| Validation Diagnostics | `validation-diagnostics-button` | View Diagnostics |
| Validation Done | `validation-done-button` | Done |

### ✅ Settings Window

#### Settings Tabs
| Tab | Identifier | Label |
|-----|------------|-------|
| Status | `settings-tab-status` | Status |
| Rules | `settings-tab-rules` | Rules |
| General | `settings-tab-general` | General |
| Repair/Remove | `settings-tab-repair` | Repair/Remove |

#### General Tab
| Element | Identifier | Label |
|---------|------------|-------|
| Open KeyPath Log | `settings-open-keypath-log-button` | Open KeyPath log |
| Open Kanata Log | `settings-open-kanata-log-button` | Open Kanata log |
| Capture Mode Picker | `settings-capture-mode-picker` | Capture Mode |
| Recording Behavior Picker | `settings-recording-behavior-picker` | Recording Behavior |
| Overlay Layout Picker | `settings-overlay-layout-picker` | Keyboard Overlay Layout |
| Overlay Keymap Picker | `settings-overlay-keymap-picker` | Keyboard Overlay Keymap |
| Include Punctuation Toggle | `settings-overlay-include-punctuation-toggle` | Include number row and punctuation |
| Reset Overlay Size | `settings-reset-overlay-size-button` | Reset Overlay Size |

#### Status Tab
| Element | Identifier | Label |
|---------|------------|-------|
| System Health Button | `status-system-health-button` | System status: [message] |
| Active Rules Button | `status-active-rules-button` | View active rules |
| Fix It Button | `status-fix-it-button` | Fix system issues |
| Service Toggle | `status-service-toggle` | Kanata Service |
| Status Action Buttons | `status-action-[action-name]` | [Action title] |

#### Rules Tab
| Element | Identifier | Label |
|---------|------------|-------|
| Create Rule Button | `rules-create-button` | Create Rule |
| Edit Config Button | `rules-edit-config-button` | Edit Config |
| Reset Button | `rules-reset-button` | Reset Rules |
| Rule Collection Toggles | `rule-toggle-[collection-id]` | Toggle [collection name] |

#### Repair/Remove Tab
| Element | Identifier | Label |
|---------|------------|-------|
| Uninstall Button | `settings-uninstall-button` | Uninstall KeyPath |
| Cleanup & Repair Button | `settings-cleanup-repair-button` | Cleanup and Repair |
| Uninstall Helper Button | `settings-uninstall-helper-button` | Uninstall Privileged Helper |
| Reset Everything Button | `settings-reset-everything-button` | Reset Everything |
| Remove Duplicates Button | `settings-remove-duplicates-button` | Remove Extra Copies |

### ✅ Keyboard Overlay

| Element | Identifier | Label |
|---------|------------|-------|
| Overlay Container | `keyboard-overlay` | KeyPath keyboard overlay |
| Drawer Toggle | `overlay-drawer-toggle` | Open/Close settings drawer |
| Close Button | `overlay-close-button` | Close keyboard overlay |
| Keymap Tab | `inspector-tab-keymap` | Keymap |
| Layout Tab | `inspector-tab-layout` | Physical Layout |
| Keycaps Tab | `inspector-tab-keycaps` | Keycap Style |
| Sounds Tab | `inspector-tab-sounds` | Typing Sounds |
| Individual Keycaps | `keycap-[key]` | Key [key], mapped to [output] |

### ✅ Installation Wizard

| Element | Identifier | Label |
|---------|------------|-------|
| Navigation Back | `wizard-nav-back` | Previous page |
| Navigation Forward | `wizard-nav-forward` | Next page |
| Close Button | `wizard-close-button` | Return to Overview |
| Step Indicators | `wizard-step-[n]-[page-id]` | Navigate to [page name] |
| Action Buttons | `wizard-button-[action-name]` | [Button title] |

**Wizard Button Examples:**
- `wizard-button-close-setup` - Close Setup
- `wizard-button-start-kanata-service` - Start Kanata Service
- `wizard-button-fix` - Fix
- `wizard-button-try-again` - Try Again
- `wizard-button-dismiss` - Dismiss

### ✅ Mapper View (Experimental)

| Element | Identifier | Label |
|---------|------------|-------|
| Toggle Inspector | `mapper-toggle-inspector-button` | Show/Hide Inspector |
| Reset Button | `mapper-reset-button` | Reset mapping |
| Advanced Behavior Toggle | `mapper-advanced-behavior-toggle` | Different actions for tap vs hold |
| Inspector Buttons | `mapper-inspector-button-[type]` | [Button title] |
| System Action Buttons | `mapper-system-action-[id]` | [Action name] |
| Clear Hold Button | `mapper-clear-hold-button` | Clear hold action |
| Clear Double Tap Button | `mapper-clear-double-tap-button` | Clear double tap action |

### ✅ Simulator View

| Element | Identifier | Label |
|---------|------------|-------|
| Delay Input | `simulator-delay-input` | Delay between events in milliseconds |
| Clear Button | `simulator-clear-button` | Clear all queued events |
| Run Button | `simulator-run-button` | Run simulation |

### ✅ Dialogs & Modals

| Element | Identifier | Label |
|---------|------------|-------|
| Emergency Stop Got It | `emergency-stop-got-it-button` | Got it |
| Uninstall Cancel | `uninstall-cancel-button` | Cancel |
| Uninstall Confirm | `uninstall-confirm-button` | Uninstall KeyPath |

## Testing with Peekaboo

### Example: Navigate Settings

```bash
# Open Settings
peekaboo menu click --app KeyPath --path "KeyPath > Settings…"

# Click Rules tab
peekaboo see --app KeyPath --json | jq -r '.data.ui_elements[] | select(.identifier == "settings-tab-rules") | .id'
peekaboo click --id elem_3 --app KeyPath

# Toggle a rule collection
peekaboo see --app KeyPath --json | jq -r '.data.ui_elements[] | select(.identifier | startswith("rule-toggle-")) | "\(.id): \(.identifier)"' | head -1
peekaboo click --id elem_10 --app KeyPath

# Click Create Rule
peekaboo click --id elem_6 --app KeyPath  # rules-create-button
```

### Example: Use Wizard

```bash
# Launch wizard
peekaboo click --id elem_2 --app KeyPath  # launch-installation-wizard-button

# Navigate forward
peekaboo click --id elem_X --app KeyPath  # wizard-nav-forward

# Click Fix button
peekaboo click --id elem_Y --app KeyPath  # wizard-button-fix
```

## Naming Conventions

### Identifiers follow these patterns:

1. **Screen prefix**: `settings-`, `wizard-`, `mapper-`, `simulator-`, `status-`
2. **Element type suffix**: `-button`, `-toggle`, `-picker`, `-input`
3. **Hierarchical**: `settings-tab-[name]`, `rule-toggle-[id]`
4. **Descriptive**: `overlay-drawer-toggle` (not `button-1`)

### Labels are human-readable:

- Use sentence case: "Open KeyPath log" (not "open keypath log")
- Be specific: "Toggle Custom Rules" (not "Toggle")
- Include context: "System status: Setup Needed" (not just "Setup Needed")

## Coverage Status

| Screen | Coverage | Status |
|--------|----------|--------|
| Main Popover | ✅ Complete | All buttons, sections, inputs |
| Settings > General | ✅ Complete | All controls, pickers, toggles |
| Settings > Status | ✅ Complete | All buttons, toggles, actions |
| Settings > Rules | ✅ Complete | All buttons, toggles (13+ collections) |
| Settings > Repair/Remove | ✅ Complete | All action buttons |
| Keyboard Overlay | ✅ Complete | Drawer, tabs, keycaps |
| Installation Wizard | ✅ Complete | Navigation, buttons, steps |
| Mapper View | ✅ Complete | All controls |
| Simulator View | ✅ Complete | All controls |
| Dialogs | ✅ Complete | All action buttons |

## Future Enhancements

- [ ] Add identifiers to wizard page-specific content (permission cards, etc.)
- [ ] Add identifiers to custom rule editor form fields
- [ ] Add identifiers to home row mods modal controls
- [ ] Add identifiers to conflict resolution dialogs

## Notes

- All identifiers use kebab-case (lowercase with hyphens)
- Labels are human-readable and descriptive
- Identifiers are stable (don't change based on state)
- Each interactive element has both `accessibilityIdentifier` and `accessibilityLabel`
