# Wizard UI HIG Compliance Review

## Current Structure Analysis

### Window Presentation
- **Current**: Custom full-screen modal with custom window frame (700x680px)
- **HIG Pattern**: Should use `NSWindow` with standard window chrome (title bar, close/minimize buttons)
- **Issue**: Custom header with "✕" button replaces standard window controls

### Navigation Pattern
- **Current**: Page dots indicator + keyboard arrow keys + custom navigation logic
- **HIG Pattern**: macOS prefers:
  - **NavigationView/NavigationStack** for hierarchical navigation
  - **Sidebar navigation** for preference panes (like System Settings)
  - **Standard Back/Forward buttons** at bottom
- **Issue**: No standard navigation controls; dots are non-standard pattern

### Button Layout
- **Current**: Custom button styles, inconsistent positioning across pages
- **HIG Pattern**: 
  - Primary action button: **Rightmost**, default (Return key)
  - Secondary actions: **Left of primary**
  - Cancel/Back: **Leftmost**
  - Destructive: Primary position with red text
- **Issue**: Button order varies; some pages have buttons centered, some right-aligned

### Page Layout
- **Current**: Custom "hero" layout with large icons (115pt), centered content
- **HIG Pattern**: 
  - **Preference pane style**: Title left-aligned, content flowing top-to-bottom
  - **Standard spacing**: 8pt grid system
  - **Group boxes**: Use `GroupBox` for related content
- **Issue**: Centered hero design doesn't match macOS preference panes

### Typography
- **Current**: Custom font sizes (23pt title, 17pt subtitle)
- **HIG Pattern**: 
  - **Title**: `.title` or `.title2` (system sizes)
  - **Body**: `.body` (13pt)
  - **Caption**: `.caption` (11pt)
- **Issue**: Non-standard sizes may not scale with system settings

### Color Usage
- **Current**: Custom colors (green, orange, red) for status
- **HIG Pattern**: 
  - Use semantic colors: `.secondary`, `.tertiary`
  - Status colors: System colors adapt to appearance
- **Issue**: Custom colors may not adapt to system appearance changes

## HIG Compliance Recommendations

### Priority 1: Navigation Structure (High Impact)

**Problem**: Wizard uses page dots and custom navigation, not standard macOS patterns.

**Solution**: Convert to **NavigationView/NavigationStack** with sidebar or step-by-step flow.

**Option A: Sidebar Navigation (Like System Settings)**
```
┌─────────────────────────────────────────┐
│ [Close]  KeyPath Setup                  │
├──────────┬──────────────────────────────┤
│ Summary  │                              │
│ Helper   │  Page Content                │
│ Perms    │                              │
│ Conflicts│                              │
│ ...      │                              │
└──────────┴──────────────────────────────┘
```

**Option B: Step-by-Step with Back/Continue (Like Installer)**
```
┌─────────────────────────────────────────┐
│ [Close]  KeyPath Setup                  │
├─────────────────────────────────────────┤
│                                          │
│  Page Content                           │
│                                          │
├─────────────────────────────────────────┤
│  [Back]              [Continue] →      │
└─────────────────────────────────────────┘
```

**Implementation**:
- Use `NavigationStack` (macOS 13+) or `NavigationView` (macOS 12)
- Add sidebar with `navigationDestination` modifiers
- Standard Back/Forward buttons in toolbar
- Remove custom page dots

**Effort**: 4-6 hours

---

### Priority 2: Button Order & Layout (Medium Impact)

**Problem**: Buttons are inconsistently positioned; order doesn't follow HIG.

**Solution**: Standardize button layout following HIG:

**HIG Rules**:
1. **Primary action**: Rightmost, default button (Return key)
2. **Cancel/Back**: Leftmost, Cancel role (Escape key)
3. **Secondary actions**: Between Cancel and Primary
4. **Destructive**: Primary position, destructive style

**Standard Layout**:
```
┌─────────────────────────────────────────┐
│                                         │
│  Content                                │
│                                         │
├─────────────────────────────────────────┤
│  [Cancel]  [Secondary]  [Continue] →  │
└─────────────────────────────────────────┘
```

**Implementation**:
- Create `WizardButtonBar` component
- Always place buttons in horizontal stack: Cancel | Secondary | Primary
- Use standard `.buttonStyle(.borderedProminent)` for primary
- Use `.keyboardShortcut(.defaultAction)` for primary button
- Use `.keyboardShortcut(.cancelAction)` for Cancel

**Files to Modify**:
- Create `WizardButtonBar.swift` component
- Update all 9 wizard pages to use standard button bar
- Ensure Return key triggers primary action
- Ensure Escape key triggers Cancel/Back

**Effort**: 2-3 hours

---

### Priority 3: Window Chrome (Medium Impact)

**Problem**: Custom header replaces standard window controls.

**Solution**: Use standard NSWindow with title bar.

**Implementation**:
- Remove custom header with "✕" button
- Use standard window close/minimize buttons
- Set window title: "KeyPath Setup"
- Use `NSWindow` title bar appearance
- Handle close via `windowShouldClose` delegate

**Code Changes**:
```swift
// In window creation:
window.title = "KeyPath Setup"
window.titleVisibility = .visible
window.titlebarAppearsTransparent = false
window.standardWindowButton(.closeButton)?.isEnabled = true
window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
```

**Effort**: 1-2 hours

---

### Priority 4: Page Layout (Low-Medium Impact)

**Problem**: Centered "hero" layout doesn't match macOS preference panes.

**Solution**: Convert to standard preference pane layout.

**HIG Pattern**:
```
┌─────────────────────────────────────────┐
│  Title (left-aligned)                   │
│                                          │
│  Description text                       │
│                                          │
│  ┌──────────────────────────────────┐  │
│  │ Group Box                         │  │
│  │ • Item 1                          │  │
│  │ • Item 2                          │  │
│  └──────────────────────────────────┘  │
│                                          │
│  [Action Button]                         │
└─────────────────────────────────────────┘
```

**Implementation**:
- Left-align titles and content
- Use `GroupBox` for related content
- Remove centered hero icons (or make them smaller, left-aligned)
- Use standard spacing: 8pt grid
- Content width: ~600px max (not full width)

**Files to Modify**:
- Update all 9 wizard pages
- Create `WizardPageLayout` component for consistency
- Replace hero layouts with standard layouts

**Effort**: 6-8 hours

---

### Priority 5: Standard Controls (Low Impact)

**Problem**: Custom button styles and controls.

**Solution**: Use standard AppKit/SwiftUI controls.

**Implementation**:
- Use `.buttonStyle(.borderedProminent)` for primary
- Use `.buttonStyle(.bordered)` for secondary
- Use standard `ProgressView` (already done)
- Use `GroupBox` for sections
- Use `Form` for form-like content

**Effort**: 2-3 hours

---

### Priority 6: Typography (Low Impact)

**Problem**: Custom font sizes that may not scale.

**Solution**: Use standard semantic font styles.

**Implementation**:
- Replace 23pt → `.title` or `.title2`
- Replace 17pt → `.body` or `.headline`
- Use system fonts that scale with accessibility settings

**Effort**: 1-2 hours

---

## Recommended Implementation Plan

### Phase 1: Quick Wins (2-3 hours)
1. **Button Order & Layout** (Priority 2)
   - Create `WizardButtonBar` component
   - Standardize button order across all pages
   - Add keyboard shortcuts (Return, Escape)

### Phase 2: Window Structure (1-2 hours)
2. **Window Chrome** (Priority 3)
   - Remove custom header
   - Use standard window controls
   - Set proper window title

### Phase 3: Navigation (4-6 hours)
3. **Navigation Structure** (Priority 1)
   - Convert to `NavigationStack`
   - Add sidebar or Back/Forward buttons
   - Remove page dots

### Phase 4: Polish (6-8 hours)
4. **Page Layout** (Priority 4)
   - Convert hero layouts to standard layouts
   - Use `GroupBox` for sections
   - Left-align content

5. **Standard Controls** (Priority 5)
   - Replace custom buttons with standard styles
   - Use standard form controls

6. **Typography** (Priority 6)
   - Replace custom sizes with semantic fonts

**Total Effort**: 15-22 hours

---

## Alternative: Minimal Changes (Recommended)

Instead of full redesign, focus on **highest-impact, lowest-effort** changes:

### Option 1: Button Order Only (2-3 hours)
- Fix button order and keyboard shortcuts
- Keep existing layout and navigation
- **Impact**: Users notice correct button behavior immediately

### Option 2: Button Order + Window Chrome (3-4 hours)
- Fix button order
- Use standard window controls
- Keep existing layout
- **Impact**: Feels more native without major restructuring

### Option 3: Button Order + Navigation (6-8 hours)
- Fix button order
- Add NavigationStack with Back/Continue
- Keep existing page layouts
- **Impact**: Standard navigation pattern users expect

---

## Specific Issues Found

### Button Order Issues

1. **WizardSummaryPage**: No standard buttons visible
2. **WizardInputMonitoringPage**: Buttons centered, not right-aligned
3. **WizardAccessibilityPage**: "Grant Permission" (primary) right, "Continue Anyway" (secondary) left ✅ Correct
4. **WizardConflictsPage**: "Fix" button position unclear
5. **WizardKarabinerComponentsPage**: Button layout unclear

### Navigation Issues

1. **Page Dots**: Non-standard pattern (iOS-style, not macOS)
2. **No Back Button**: Users can't easily go back
3. **No Continue Button**: Must use dots or keyboard arrows
4. **Keyboard Navigation**: Arrow keys work, but not discoverable

### Layout Issues

1. **Centered Content**: Hero layout doesn't match macOS preference panes
2. **Large Icons**: 115pt icons are iOS-style, not macOS
3. **No Group Boxes**: Related content not grouped visually
4. **Inconsistent Spacing**: Custom spacing values don't follow 8pt grid

---

## Conclusion

**Biggest Issues**:
1. ❌ No standard navigation controls (Back/Continue buttons)
2. ❌ Button order not consistently following HIG
3. ❌ Custom window chrome instead of standard controls
4. ⚠️ Centered hero layout (works, but not macOS-native)

**Recommended Approach**:
Start with **Button Order + Window Chrome** (3-4 hours) for quick, high-impact improvement. Then evaluate if full navigation restructure is needed.

**Full HIG Compliance**: 15-22 hours total
**Quick Wins**: 2-4 hours for button order + window chrome
