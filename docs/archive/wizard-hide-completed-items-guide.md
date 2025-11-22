# Wizard Hide Completed Items - Implementation Guide

## Overview

This feature adds progressive disclosure to wizard detail pages:
- **Default**: Hide completed/green items, only show issues
- **On icon click**: Toggle to show all items + refresh state
- **Hover effect**: Subtle ring on icon indicates it's clickable

## Completed Pages

✅ **WizardHeroSection.swift** - Hover effect on icon (universal)
✅ **WizardKarabinerComponentsPage.swift** - Show/hide logic (reference implementation)

## Pages to Update

- [ ] WizardInputMonitoringPage.swift
- [ ] WizardAccessibilityPage.swift
- [ ] WizardKanataComponentsPage.swift
- [ ] WizardHelperPage.swift
- [ ] WizardConflictsPage.swift
- [ ] WizardKanataServicePage.swift
- [ ] WizardCommunicationPage.swift
- [ ] WizardFullDiskAccessPage.swift

## Implementation Pattern

### Step 1: Add State Variable

At the top of the view struct, add the state variable:

```swift
@State private var showAllItems = false
```

### Step 2: Update Hero Icon Tap Action

Find the `WizardHeroSection` and update the `iconTapAction`:

**Before:**
```swift
iconTapAction: {
    Task {
        await onRefresh()
    }
}
```

**After:**
```swift
iconTapAction: {
    showAllItems.toggle()
    Task {
        await onRefresh()
    }
}
```

**Note:** If the page uses sync `onRefresh()` (not async), use:
```swift
iconTapAction: {
    showAllItems.toggle()
    onRefresh()
}
```

### Step 3: Wrap Items with Conditional Display

For each item in the detail list, wrap with a conditional:

**Pattern:**
```swift
if showAllItems || itemStatus != .completed {
    // Item view (HStack with icon, text, optional Fix button)
}
```

**Success State Example** (all items completed):
```swift
// Only show when user clicks icon to expand
if showAllItems {
    HStack(spacing: 12) {
        Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
        HStack(spacing: 0) {
            Text("Item Name")
                .font(.headline)
                .fontWeight(.semibold)
            Text(" - Description")
                .font(.headline)
                .fontWeight(.regular)
        }
    }
}
```

**Error State Example** (mixed completed/failed items):
```swift
// Show if expanded OR if item has issues
if showAllItems || keyPathStatus != .completed {
    HStack(spacing: 12) {
        Image(systemName: keyPathStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundColor(keyPathStatus == .completed ? .green : .red)
        HStack(spacing: 0) {
            Text("KeyPath.app")
                .font(.headline)
                .fontWeight(.semibold)
            Text(" - Description")
                .font(.headline)
                .fontWeight(.regular)
        }
        Spacer()
        if keyPathStatus != .completed {
            Button("Fix") {
                handleFix()
            }
            .buttonStyle(WizardDesign.Component.SecondaryButton())
            .scaleEffect(0.8)
        }
    }
}

// Second item
if showAllItems || kanataStatus != .completed {
    HStack(spacing: 12) {
        // ... similar structure
    }
}
```

## Reference Implementation: WizardKarabinerComponentsPage

### Complete Diff

```swift
// 1. Add state
@State private var showAllItems = false

// 2. Update hero section (success state)
WizardHeroSection.success(
    icon: "keyboard.macwindow",
    title: "Karabiner Driver",
    subtitle: "Virtual keyboard driver is installed & configured",
    iconTapAction: {
        showAllItems.toggle()  // ← Added
        Task {
            onRefresh()
        }
    }
)

// 3. Wrap items (success state)
VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
    // Show Karabiner Driver only if showAllItems
    if showAllItems {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            HStack(spacing: 0) {
                Text("Karabiner Driver")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(" - Virtual keyboard driver")
                    .font(.headline)
                    .fontWeight(.regular)
            }
        }
    }

    // Show Background Services only if showAllItems OR if it has issues
    if showAllItems || componentStatus(for: .backgroundServices) != .completed {
        HStack(spacing: 12) {
            Image(systemName: componentStatus(for: .backgroundServices) == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(componentStatus(for: .backgroundServices) == .completed ? .green : .red)
            HStack(spacing: 0) {
                Text("Background Services")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(" - Login Items")
                    .font(.headline)
                    .fontWeight(.regular)
            }
        }
    }
}

// 4. Update hero section (error state)
WizardHeroSection.warning(
    icon: "keyboard.macwindow",
    title: "Karabiner Driver Required",
    subtitle: "Karabiner virtual keyboard driver needs to be installed",
    iconTapAction: {
        showAllItems.toggle()  // ← Added
        Task {
            onRefresh()
        }
    }
)

// 5. Wrap items (error state) - same pattern as success
```

## Page-Specific Notes

### WizardInputMonitoringPage

**Items to wrap:**
1. KeyPath.app (Input Monitoring)
2. kanata (Input Monitoring)

**Status variables:**
- `keyPathInputMonitoringStatus`
- `kanataInputMonitoringStatus`

**Pattern:**
```swift
if showAllItems || keyPathInputMonitoringStatus != .completed {
    // KeyPath.app item
}

if showAllItems || kanataInputMonitoringStatus != .completed {
    // kanata item
}
```

### WizardAccessibilityPage

**Items to wrap:**
1. KeyPath.app (Accessibility)
2. kanata (Accessibility)

**Status variables:**
- `keyPathAccessibilityStatus`
- `kanataAccessibilityStatus`

### WizardKanataComponentsPage

**Items to wrap:**
1. Kanata Binary
2. Kanata Service (if applicable)

**Status check:**
- Look for `componentStatus(for:)` calls

### WizardHelperPage

**Items to wrap:**
1. Privileged Helper installation
2. Helper health/functionality

**Pattern:**
```swift
if showAllItems || helperStatus != .completed {
    // Helper item
}
```

### WizardConflictsPage

**Special case:** This page lists conflicts, which are always issues.

**Recommendation:**
- Don't hide items (conflicts are always problems to fix)
- Still add `showAllItems.toggle()` to icon tap for consistency with refresh
- Or skip this page entirely

### WizardKanataServicePage

**Items to wrap:**
1. Kanata Service running status

**Single item pages:** May not need hide/show logic, but add toggle for consistency

### WizardCommunicationPage

**Items to wrap:**
1. TCP Server configuration
2. TCP Server connectivity

### WizardFullDiskAccessPage

**Single item page:** Probably doesn't need hide/show logic

## Testing Checklist

After updating each page:

1. ✅ Build compiles without errors
2. ✅ Success state hides items by default
3. ✅ Clicking icon shows all items
4. ✅ Clicking icon again hides completed items
5. ✅ Error state shows only items with issues by default
6. ✅ Hover effect appears on icon (from WizardHeroSection)
7. ✅ Refresh still works after toggling

## Common Pitfalls

### 1. Incorrect Nesting

❌ **Wrong:**
```swift
VStack {
    if showAllItems {
        HStack { ... }
    }
    .help(...)  // ← .help applied to 'if' block, not HStack
}
```

✅ **Correct:**
```swift
VStack {
    if showAllItems {
        HStack { ... }
            .help(...)  // ← .help inside 'if' block
    }
}
```

### 2. Missing Spacer() in Error State

Some items have `Spacer()` before the Fix button. Make sure it stays inside the `if` block:

```swift
if showAllItems || status != .completed {
    HStack {
        // Icon and text
        Spacer()  // ← Keep this inside
        if status != .completed {
            Button("Fix") { }
        }
    }
}
```

### 3. Forgetting Both States

Remember to update BOTH success and error hero sections:
- Success state (green checkmark overlay)
- Error/Warning state (red/orange overlay)

## Visual Behavior

**Default state (showAllItems = false):**
- Success page: Empty/minimal (all items hidden)
- Error page: Only shows items with issues

**Expanded state (showAllItems = true):**
- Shows ALL items regardless of status
- Green items use `checkmark.circle.fill`
- Red items use `xmark.circle.fill`

**Icon behavior:**
- Hover: Subtle ring appears (0.15 opacity)
- Click: Toggles showAllItems + refreshes state

## Example Test Scenario

1. **Initial load:**
   - WizardKarabinerComponentsPage opens
   - Karabiner Driver: ✅ completed
   - Background Services: ❌ failed

2. **Default view:**
   - Shows: Background Services (red X + Fix button)
   - Hidden: Karabiner Driver (completed)

3. **User hovers icon:**
   - Ring appears around icon

4. **User clicks icon:**
   - showAllItems = true
   - Refresh triggered
   - Shows: Both items (driver in green, services in red)

5. **User clicks icon again:**
   - showAllItems = false
   - Hidden: Karabiner Driver (completed)
   - Shows: Background Services (still has issue)

## Migration Order (Recommended)

1. ✅ WizardKarabinerComponentsPage (completed - reference)
2. WizardInputMonitoringPage (similar 2-item structure)
3. WizardAccessibilityPage (similar 2-item structure)
4. WizardHelperPage (single item, simpler)
5. WizardKanataComponentsPage (1-2 items)
6. WizardKanataServicePage (single item)
7. WizardCommunicationPage (2 items: config + connectivity)
8. WizardConflictsPage (special case - may skip)
9. WizardFullDiskAccessPage (single item - may skip)

## Questions?

Reference files:
- `Sources/KeyPath/InstallationWizard/UI/Components/WizardHeroSection.swift` (hover effect)
- `Sources/KeyPath/InstallationWizard/UI/Pages/WizardKarabinerComponentsPage.swift` (complete example)

Pattern is consistent across all pages - just adapt to each page's specific items and status checks.
