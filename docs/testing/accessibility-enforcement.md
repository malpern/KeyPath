# Accessibility Enforcement Guide

**Last Updated:** December 24, 2025

## Overview

KeyPath enforces accessibility identifier requirements through multiple layers to ensure all UI elements are automatable and testable.

## Enforcement Layers

### 1. ✅ Pre-Commit Hook (Local)

**Location:** `.git/hooks/pre-commit`

**What it does:**
- Runs `check-accessibility.py` on staged UI files
- Shows warnings for missing identifiers
- **Currently non-blocking** (allows gradual adoption)

**To enable blocking:**
```bash
# Edit .git/hooks/pre-commit
# Uncomment: exit 1
```

**To skip (emergency only):**
```bash
git commit --no-verify -m "emergency fix"
```

### 2. ✅ CI Check (GitHub Actions)

**Location:** `.github/workflows/ci.yml`

**What it does:**
- Runs accessibility check on all UI files
- Reports issues in CI summary
- **Currently non-blocking** (allows gradual adoption)

**Status:** ✅ Active (warning only)

### 3. ✅ SwiftLint Custom Rule

**Location:** `.swiftlint.yml`

**What it does:**
- Regex-based pattern matching for Button/Toggle/Picker
- Flags potential missing identifiers
- **Warning severity** (doesn't fail builds)

**Rule:**
```yaml
require_accessibility_identifier:
  name: "Missing Accessibility Identifier"
  regex: '(Button|Toggle|Picker)\s*\([^)]*\)[^.]*\.(buttonStyle|toggleStyle|pickerStyle)'
  message: "Interactive UI element should have .accessibilityIdentifier() modifier"
  severity: warning
```

**Limitations:**
- Regex-based (can't parse Swift AST)
- May have false positives/negatives
- Used as a reminder, not enforcement

### 4. ✅ Python Script (Primary Enforcement)

**Location:** `Scripts/check-accessibility.py`

**What it does:**
- Parses Swift files for Button/Toggle/Picker patterns
- Checks for `.accessibilityIdentifier()` modifier within 30 lines
- Excludes system components, alerts, custom wrappers
- **Most accurate** enforcement mechanism

**Usage:**
```bash
# Check all UI files
python3 Scripts/check-accessibility.py

# Exit code: 0 = all good, 1 = issues found
```

## Current Status

### ✅ Covered (50+ identifiers)
- Settings window (all tabs, buttons, toggles)
- Installation Wizard (navigation, buttons, steps)
- Keyboard Overlay (drawer, tabs, keycaps)
- Main Popover (recording sections, wizard button)
- Mapper View (all controls)
- Simulator View (all controls)

### ⚠️ Partially Covered
- Rules editor modals (some buttons missing)
- Home row mods dialogs (some controls missing)
- Custom rule editor (form fields need IDs)
- Overlay inspector content (some pickers missing)

### ❌ Not Yet Covered
- Alert buttons (system dialogs - lower priority)
- Some experimental views
- Legacy views being phased out

## Gradual Adoption Strategy

### Phase 1: Warning Only (Current)
- ✅ Pre-commit hook warns but doesn't block
- ✅ CI reports but doesn't fail
- ✅ Developers see reminders

### Phase 2: Block New Code (Future)
- Pre-commit hook blocks commits with missing identifiers
- CI fails on new files without identifiers
- Existing code grandfathered

### Phase 3: Full Enforcement (Future)
- All UI files must pass check
- Pre-commit hook blocks all violations
- CI fails on any missing identifiers

## How to Fix Issues

### Step 1: Run Check
```bash
python3 Scripts/check-accessibility.py
```

### Step 2: Add Identifiers
```swift
// Before
Button("Save") {
    save()
}

// After
Button("Save") {
    save()
}
.accessibilityIdentifier("settings-save-button")
.accessibilityLabel("Save settings")
```

### Step 3: Verify
```bash
python3 Scripts/check-accessibility.py
# Should show: ✅ All UI elements have accessibility identifiers!
```

## Exceptions

### System Components
- `NSButton`, `NSToggle`, `NSPopUpButton` - Use system accessibility APIs
- Toolbar items - System-managed
- Window controls - System-managed

### Custom Components
- `InspectorButton`, `WizardButton` - Add identifiers internally
- Custom wrappers - Should add identifiers in component definition

### Alerts/Sheets
- Alert buttons - System dialogs (lower priority)
- Sheet buttons - Can add identifiers but may not be discoverable

## Testing Your Changes

### Manual Test with Peekaboo
```bash
# 1. Deploy your changes
./Scripts/quick-deploy.sh

# 2. Open the UI element
peekaboo see --app KeyPath --json | jq '.data.ui_elements[] | select(.identifier == "your-new-id")'

# 3. Click it
peekaboo click --id elem_X --app KeyPath
```

### Automated Test
```bash
# Run accessibility check
python3 Scripts/check-accessibility.py

# Should pass before committing
```

## Best Practices

1. **Add identifiers immediately** when creating new UI elements
2. **Use consistent naming** (see ACCESSIBILITY_COVERAGE.md)
3. **Test with Peekaboo** to verify identifiers work
4. **Don't skip the check** - fix issues before committing

## Troubleshooting

### "Script not found"
```bash
chmod +x Scripts/check-accessibility.py
```

### "Python not found"
```bash
# macOS includes Python 3
python3 --version

# Or install via Homebrew
brew install python3
```

### "Too many false positives"
- Update exclusion patterns in `check-accessibility.py`
- Add custom component detection
- File an issue with examples

### "Pre-commit hook not running"
```bash
# Reinstall hook
chmod +x .git/hooks/pre-commit
```

## Future Improvements

- [ ] AST-based parsing (more accurate than regex)
- [ ] IDE integration (Xcode warnings)
- [ ] Auto-fix capability (add identifiers automatically)
- [ ] Coverage reporting (track % of elements covered)

## Related Documentation

- [ACCESSIBILITY_COVERAGE.md](../ACCESSIBILITY_COVERAGE.md) - Complete identifier reference
- [CONTRIBUTING.md](../CONTRIBUTING.md) - General contribution guidelines
- [CLAUDE.md](../CLAUDE.md) - Architecture details
