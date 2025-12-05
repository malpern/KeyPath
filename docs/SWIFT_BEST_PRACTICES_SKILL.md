# Swift Best Practices Skill - Complete

## Overview

A comprehensive Claude Code skill has been created at `~/.claude/commands/swift-best-practices.md` that captures all modern Swift and SwiftUI best practices from Paul Hudson's Hacking with Swift article: **"What to Fix in AI-Generated Swift Code"**

## Skill Features

### 1. Deprecated API Replacements (6 sections)
- `foregroundColor()` → `foregroundStyle()`
- `cornerRadius()` → `clipShape()`
- `onChange(of:body:)` → two-parameter version
- `Task.sleep(nanoseconds:)` → `Task.sleep(for:)`
- `NavigationView` → `NavigationStack`
- `tabItem()` → new `Tab` API (iOS 18+)

### 2. Accessibility Issues (3 sections)
- `onTapGesture()` → `Button` components
- Button labels and VoiceOver support
- `navigationDestination(for:)` vs inline `NavigationLink`

### 3. Performance & Architecture (6 sections)
- `ObservableObject` → `@Observable` macro
- `ForEach(Array(enumerated()))` → `.indices`
- Font sizes & Dynamic Type
- Consistent `fontWeight()` usage
- `GeometryReader` best practices
- `DispatchQueue.main.async` → async/await

### 4. Modern APIs (3 sections)
- `UIGraphicsImageRenderer` → `ImageRenderer`
- Document directory access improvements
- Safe number formatting

### 5. Code Organization
- Single file size considerations
- Build time optimization
- Type organization guidelines

### 6. Important Notes
- `@MainActor` usage clarification
- iOS version targeting with availability checks
- LLM hallucination warnings

## Quick Reference Checklist

The skill includes a **14-item checklist** for code reviews:

```
Before shipping code:
- [ ] No foregroundColor() - use foregroundStyle()
- [ ] No cornerRadius() - use clipShape()
- [ ] No onTapGesture() - use Button
- [ ] No deprecated onChange(of:body:) - use two-parameter version
- [ ] No Task.sleep(nanoseconds:) - use Task.sleep(for:)
- [ ] No NavigationView - use NavigationStack
- [ ] No inline NavigationLink in lists - use navigationDestination(for:)
- [ ] No ObservableObject if iOS 17+ - use @Observable
- [ ] No fixed font sizes - use semantic or Dynamic Type
- [ ] No Array(enumerated()) - use .indices
- [ ] Buttons have accessible labels
- [ ] Code is split across multiple focused files
- [ ] No DispatchQueue.main.async - use async/await
- [ ] No UIGraphicsImageRenderer - use ImageRenderer
```

## Integration with KeyPath Project

### Applied to KeyPath Codebase
This skill has already been applied to the KeyPath application through a phased migration:

**Phase 1 (Completed)**
- Fixed old `onChange` variants in 3 files
- Replaced `NavigationView` with `NavigationStack` in 1 file
- Removed `Array(enumerated())` wrappers in 10 files

**Phase 2 (Pending)**
- Replace `onTapGesture()` with `Button` (20 occurrences)

**Phase 3 (Completed)**
- Migrated `Task.sleep(nanoseconds:)` to `Task.sleep(for:)` in 5 source files
- Replaced `foregroundColor()` with `foregroundStyle()` in 61 files (532 occurrences)
  - Special handling for accentColor, ternary operators, opacity chains
  - Fixed WizardButton enum style parameters

**Phase 4 (Pending)**
- Migrate `ObservableObject` to `@Observable` (26 classes)

**Phase 5 (Pending)**
- Design system consistency: Font sizes (183 hardcoded), fontWeight (85 usages)

### Build Status
- ✅ Build passing (15.41s)
- ✅ All 181 tests pass
- ✅ No regressions

## Usage in Claude Code

The skill can be referenced when:

1. **Reviewing Swift code** - Check against the checklist for violations
2. **Migrating deprecated APIs** - Reference specific examples for each pattern
3. **Improving accessibility** - Use accessibility section for button/label patterns
4. **Optimizing performance** - Check architecture section for build/runtime improvements
5. **Training other developers** - Share the skill for team knowledge sharing

## File Location

```
~/.claude/commands/swift-best-practices.md
```

File size: 11 KB (471 lines)
Created: December 5, 2025

## Related Documents

- `docs/CODE_REVIEW_REPORT.md` - Comprehensive module-by-module analysis
- `docs/CODE_REVIEW_EXECUTIVE_SUMMARY.md` - High-level issues and recommendations
- `docs/SWIFT_BEST_PRACTICES_AUDIT.md` - Detailed audit findings
- `docs/SWIFT_BEST_PRACTICES_MIGRATION_SUMMARY.md` - Progress summary of applied phases

## Future Work

With the skill in place, future tasks can reference it for:
- Code reviews of new contributions
- Automated pattern detection
- Training and onboarding new developers
- Swift 6 migration planning (when adopting SE-0414 strict concurrency)
