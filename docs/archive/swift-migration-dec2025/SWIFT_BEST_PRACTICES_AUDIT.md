# Swift Best Practices Audit

**Reference:** [Hacking with Swift - What to Fix in AI-Generated Swift Code](https://www.hackingwithswift.com/articles/281/what-to-fix-in-ai-generated-swift-code)

**Date:** December 5, 2025

---

## Summary

| Issue | Occurrences | Priority | Action |
|-------|-------------|----------|--------|
| `foregroundColor()` deprecated | 532 | 🟡 Medium | Replace with `foregroundStyle()` |
| `Task.sleep(nanoseconds:)` deprecated | 73 | 🟠 High | Replace with `Task.sleep(for:)` |
| `DispatchQueue.main.async` overuse | 74 | 🟡 Medium | Use async/await or @MainActor |
| `.fontWeight()` overuse | 85 | 🟢 Low | Consider semantic font styles |
| Hardcoded font sizes | 183 | 🟡 Medium | Use Dynamic Type |
| `cornerRadius()` deprecated | 57 | 🟢 Low | Replace with `clipShape()` |
| `ObservableObject` pattern | 26 | 🟡 Medium | Consider `@Observable` macro |
| `onTapGesture` accessibility | 20 | 🟠 High | Replace with `Button` |
| `GeometryReader` overuse | 9 | 🟢 Low | Consider alternatives |
| `Array(x.enumerated())` in ForEach | 11 | 🟢 Low | Use direct iteration |
| `NavigationView` deprecated | 1 | 🟢 Low | Replace with `NavigationStack` |
| Old `onChange(of:)` variant | 3 | 🟡 Medium | Use two-parameter variant |

---

## Detailed Findings

### 🟠 HIGH PRIORITY

#### 1. `Task.sleep(nanoseconds:)` - 73 occurrences

**Issue:** Using deprecated nanosecond-based sleep API.

**Current:**
```swift
try await Task.sleep(nanoseconds: 1_000_000_000)
```

**Recommended:**
```swift
try await Task.sleep(for: .seconds(1))
```

**Files affected:** 34 files including:
- `KanataTCPClient.swift` (8 occurrences)
- `RecordingCoordinatorTests.swift` (5 occurrences)
- `SystemValidatorTests.swift` (4 occurrences)
- `SimpleModsService.swift` (4 occurrences)
- `PrivilegedOperationsCoordinator.swift` (4 occurrences)

**Migration effort:** ~2 hours (simple find-replace with unit conversion)

---

#### 2. `onTapGesture` Accessibility Issues - 20 occurrences

**Issue:** `onTapGesture` is poor for VoiceOver and visionOS. Interactive elements should be `Button`.

**Current:**
```swift
Image(systemName: "xmark")
    .onTapGesture { dismiss() }
```

**Recommended:**
```swift
Button("Close", systemImage: "xmark") { dismiss() }
```

**Files affected:** 12 files including:
- `CustomRuleEditorView.swift` (5 occurrences)
- `MapperView.swift` (3 occurrences)
- `SimulatorKeycapView.swift` (1 occurrence)

**Migration effort:** ~1-2 hours (review each case for proper labeling)

---

### 🟡 MEDIUM PRIORITY

#### 3. `foregroundColor()` Deprecated - 532 occurrences

**Issue:** `foregroundColor()` lacks gradient support and is deprecated in favor of `foregroundStyle()`.

**Current:**
```swift
Text("Hello").foregroundColor(.red)
```

**Recommended:**
```swift
Text("Hello").foregroundStyle(.red)
// Or with gradients:
Text("Hello").foregroundStyle(.linearGradient(...))
```

**Files affected:** 61 files

**Migration effort:** ~4 hours (bulk find-replace, but verify gradient cases)

**Note:** This is a non-breaking deprecation. The old API still works, but new code should use `foregroundStyle()`.

---

#### 4. `DispatchQueue.main.async` Overuse - 74 occurrences

**Issue:** Modern Swift concurrency provides cleaner alternatives.

**Current:**
```swift
DispatchQueue.main.async {
    self.isLoading = false
}
```

**Recommended:**
```swift
await MainActor.run {
    isLoading = false
}
// Or mark the containing function @MainActor
```

**Files affected:** 42 files including:
- `KeyboardCaptureTests.swift` (10 occurrences)
- `ContentView.swift` (7 occurrences)
- `KeyboardCapture.swift` (4 occurrences)

**Migration effort:** ~3-4 hours (requires careful analysis of context)

---

#### 5. Hardcoded Font Sizes - 183 occurrences

**Issue:** Using `.font(.system(size: 14))` ignores Dynamic Type accessibility settings.

**Current:**
```swift
Text("Label").font(.system(size: 14))
```

**Recommended:**
```swift
Text("Label").font(.body)
// Or for custom sizing that scales:
Text("Label").font(.system(.body, design: .rounded))
```

**Files affected:** 39 files including:
- `OverlayKeycapView.swift` (16 occurrences)
- `CleanupAndRepairView.swift` (16 occurrences)
- `MapperView.swift` (14 occurrences)
- `WizardDesignSystem.swift` (12 occurrences)

**Migration effort:** ~4-6 hours (requires design review for each size)

**Mitigation:** KeyPath is a macOS-only app where Dynamic Type is less critical than iOS. However, using semantic fonts improves consistency.

---

#### 6. `ObservableObject` vs `@Observable` - 26 classes

**Issue:** The `@Observable` macro (iOS 17+/macOS 14+) is simpler and more performant than `ObservableObject` with `@Published`.

**Current:**
```swift
class ViewModel: ObservableObject {
    @Published var count = 0
}

struct MyView: View {
    @StateObject var viewModel = ViewModel()
}
```

**Recommended:**
```swift
@Observable
class ViewModel {
    var count = 0
}

struct MyView: View {
    @State var viewModel = ViewModel()
}
```

**Classes affected:**
- `KanataViewModel`
- `RuntimeCoordinator`
- `WizardStateManager`
- `WizardStateMachine`
- `WizardNavigationCoordinator`
- `SimulatorViewModel`
- And 20 more...

**Migration effort:** ~8-12 hours (requires testing each view that uses these)

**Consideration:** KeyPath already uses 4 `@Observable` classes. This is a gradual migration opportunity.

---

#### 7. Old `onChange(of:)` Single-Parameter Variant - ~3 occurrences

**Issue:** The single-parameter variant is deprecated and unsafe.

**Current:**
```swift
.onChange(of: value) { newValue in
    // ...
}
```

**Recommended:**
```swift
.onChange(of: value) { oldValue, newValue in
    // ...
}
// Or if you don't need old value:
.onChange(of: value) { _, newValue in
    // ...
}
```

**Files affected:**
- `WizardSystemStatusOverview.swift` (1 occurrence found using old style)

**Migration effort:** ~30 minutes

**Note:** Most of KeyPath already uses the two-parameter variant (46 occurrences).

---

### 🟢 LOW PRIORITY

#### 8. `cornerRadius()` Deprecated - 57 occurrences

**Issue:** `cornerRadius()` doesn't support uneven corners.

**Current:**
```swift
view.cornerRadius(8)
```

**Recommended:**
```swift
view.clipShape(.rect(cornerRadius: 8))
// Or for uneven corners:
view.clipShape(.rect(cornerRadii: .init(topLeading: 8, bottomTrailing: 8)))
```

**Files affected:** 27 files

**Migration effort:** ~2 hours

---

#### 9. `.fontWeight()` Overuse - 85 occurrences

**Issue:** Excessive use of `fontWeight()` can conflict with Dynamic Type.

**Files affected:** 22 files including:
- `HelpSheets.swift` (20 occurrences)
- `WizardInputMonitoringPage.swift` (11 occurrences)

**Migration effort:** ~2 hours (review necessity of each)

**Note:** Many uses are intentional for visual hierarchy. Review case-by-case.

---

#### 10. `GeometryReader` - 9 occurrences

**Issue:** Can cause layout issues and performance problems.

**Files affected:**
- `WizardSystemStatusOverview.swift` (2)
- `WizardProgressIndicator.swift` (2)
- `MapperView.swift` (1)
- And 4 more...

**Alternatives to consider:**
- `containerRelativeFrame()` for container-relative sizing
- `visualEffect()` for reading geometry without layout impact

**Migration effort:** ~2 hours (requires case-by-case analysis)

---

#### 11. `Array(x.enumerated())` Pattern - 11 occurrences

**Issue:** Unnecessary Array wrapper in ForEach.

**Current:**
```swift
ForEach(Array(items.enumerated()), id: \.offset) { index, item in
    // ...
}
```

**Recommended:**
```swift
ForEach(items.indices, id: \.self) { index in
    let item = items[index]
    // ...
}
// Or use item ID directly if available
```

**Files affected:** 10 files

**Migration effort:** ~1 hour

---

#### 12. `NavigationView` Deprecated - 1 occurrence

**File:** `InstallerView.swift`

**Migration effort:** ~15 minutes (replace with `NavigationStack`)

---

## What KeyPath is Already Doing Well

✅ **No `tabItem()` usage** - N/A for macOS, but good for future visionOS compatibility

✅ **Using `NavigationStack`** - 1 occurrence in `SimpleModsView.swift`

✅ **Using `@Observable`** - 4 classes already migrated

✅ **No `UIGraphicsImageRenderer`** - Correct for macOS (would be AppKit equivalent)

✅ **No legacy documents directory access** - Using modern APIs

✅ **Two-parameter `onChange`** - 46 of 49 usages are correct

✅ **No inline `NavigationLink(destination:)`** - Not using deprecated pattern

---

## Recommended Migration Order

### Phase 1: Quick Wins (2-3 hours)
1. Fix single-parameter `onChange` (~3 occurrences)
2. Replace `NavigationView` with `NavigationStack` (1 file)
3. Remove `Array(x.enumerated())` wrappers (11 occurrences)

### Phase 2: Accessibility Improvements (3-4 hours)
1. Replace `onTapGesture` with `Button` for interactive elements (20 occurrences)
2. Audit icon-only buttons for accessibility labels

### Phase 3: Deprecation Cleanup (6-8 hours)
1. Replace `Task.sleep(nanoseconds:)` with `Task.sleep(for:)` (73 occurrences)
2. Replace `foregroundColor()` with `foregroundStyle()` (532 occurrences)
3. Replace `cornerRadius()` with `clipShape()` (57 occurrences)

### Phase 4: Modern Swift Patterns (8-12 hours)
1. Migrate `DispatchQueue.main.async` to async/await (74 occurrences)
2. Gradually migrate `ObservableObject` to `@Observable` (26 classes)

### Phase 5: Design System Consistency (4-6 hours)
1. Review hardcoded font sizes (183 occurrences)
2. Create semantic font tokens in design system
3. Audit `fontWeight` usage (85 occurrences)

---

## Automated Migration Commands

```bash
# Phase 1: Task.sleep migration (run from project root)
# Note: Manual review needed for nanosecond calculations
find Sources -name "*.swift" -exec grep -l "Task.sleep(nanoseconds:" {} \;

# Phase 3: foregroundColor migration
find Sources -name "*.swift" -exec sed -i '' 's/\.foregroundColor(/\.foregroundStyle(/g' {} \;

# Verify changes compile
swift build
```

---

## Total Estimated Effort

| Phase | Hours |
|-------|-------|
| Phase 1: Quick Wins | 2-3 |
| Phase 2: Accessibility | 3-4 |
| Phase 3: Deprecations | 6-8 |
| Phase 4: Modern Patterns | 8-12 |
| Phase 5: Design System | 4-6 |
| **Total** | **23-33 hours** |

---

*Audit based on Hacking with Swift best practices guide by Paul Hudson*
