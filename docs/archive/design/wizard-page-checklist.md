# Wizard Page Checklist

This checklist ensures all wizard pages follow consistent design patterns and use reusable components.

## ✅ Completed Standards

### Component Usage
- [x] Use `WizardHeroSection` for hero sections (icon + title + subtitle)
- [x] Use `WizardNavigationControl` via `.wizardDetailPage()` modifier
- [x] Use `CloseButton` for top-right close button

### Layout & Spacing
- [x] Hero sections use `WizardDesign.Spacing.pageVertical` (20pt) for top/bottom padding
- [x] Hero sections use `WizardDesign.Spacing.sectionGap` (16pt) between icon, title, and subtitle
- [x] Window uses `.fixedSize(horizontal: false, vertical: true)` to allow vertical growth
- [x] Window width fixed, height grows based on content

### Typography
- [x] Hero icons: 115pt, `.light` weight
- [x] Hero titles: 23pt, `.semibold` weight
- [x] Hero subtitles: 17pt, `.regular` weight

### Icon Overlays
- [x] Success state: Large overlay (40pt, offset x:15 y:-5, frame 140x115)
- [x] Warning/Error state: Small overlay (24pt, offset x:8 y:-3, frame 60x60)

## 📋 Pages to Update

### Updated to Use WizardHeroSection
- [x] `WizardKanataComponentsPage` - Success and warning states

### Need Update
- [ ] `WizardKanataServicePage` - Success and warning states
- [ ] `WizardKarabinerComponentsPage` - Success and warning states
- [ ] `WizardHelperPage` - Error/warning state
- [ ] `WizardFullDiskAccessPage` - Success and info states
- [ ] `WizardCommunicationPage` - Success and warning states
- [ ] `WizardConflictsPage` - Warning state
- [ ] `WizardAccessibilityPage` - (if has hero section)
- [ ] `WizardInputMonitoringPage` - (if has hero section)

## 🔍 Verification Checklist

For each page, verify:
1. Hero section uses `WizardHeroSection` component
2. Icon size is 115pt
3. Title is 23pt semibold
4. Subtitle is 17pt regular
5. Spacing matches design system constants
6. Window grows vertically when needed
7. Navigation control present (if detail page)
8. Close button present (if detail page)

## 📝 Notes

- `WizardHeroSection` provides convenience initializers:
  - `.success()` - Green icon with large checkmark overlay
  - `.warning()` - Orange icon with small warning overlay
  - `.error()` - Red icon with small error overlay
- Custom overlays can be specified using the full initializer
- Action buttons are optional and appear below subtitle

