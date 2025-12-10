# Wizard Installer Improvements Plan

Based on the holistic review completed December 9, 2025.

## Overview

The wizard installer codebase is production-ready. These are nice-to-have improvements that will increase robustness and maintainability.

---

## Task 1: Add Explicit ADR-026 Invariant Test

**Priority:** High (prevents regression of critical invariant)
**Effort:** Small (~30 min)
**Status:** ✅ ALREADY COMPLETE

### Discovery
Upon review, comprehensive ADR-026 tests already exist:
- `Tests/KeyPathTests/Services/SystemSnapshotADR026Tests.swift` (5 tests)
- `Tests/KeyPathTests/Services/PermissionOracleTCCTests.swift` (additional coverage)

### Existing Test Coverage
1. `blockingIssuesNeverIncludeKanataPermissions` - Verifies no Kanata permission issues generated
2. `onlyKeyPathPermissionIssuesGenerated` - Verifies only KeyPath issues appear
3. `validatePassesWithKeyPathPermissionsOnly` - Tests the assertion in `validate()`
4. `kanataStatesDoNotAffectIssueCount` - Tests all Kanata state combinations
5. `issueTitleNeverMentionsKanataForPermissions` - Verifies issue titles

### Verification
```bash
swift test --filter "ADR026"
# ✅ 5/5 tests pass
```

### Conclusion
No additional work needed - ADR-026 invariant is already comprehensively tested.

---

## Task 2: Add Retry Logic for VHID Driver Download

**Priority:** Medium (network operations can fail)
**Effort:** Medium (~1-2 hours)
**Status:** ✅ NOT APPLICABLE

### Discovery
Upon code review, the wizard installer **has no network download operations**:

1. **VHIDDeviceManager.downloadAndInstallCorrectVersion()** - Uses a **bundled pkg file** from `WizardSystemPaths.bundledVHIDDriverPkgPath`. No network download.

2. **PackageManager** - Only contains a comment mentioning download URL for manual fallback instructions. No actual download code.

3. All URL operations in the wizard are for opening System Preferences (local `x-apple.systempreferences:` URLs).

### Where Network Calls Exist (Outside Wizard)
- `AnthropicConfigRepairService.swift` - AI config repair (optional feature)
- `KanataConfigGenerator.swift` - AI config generation (optional feature)

These are non-critical optional features, not part of the core installation flow.

### Conclusion
No retry logic needed for the wizard installer - it operates entirely locally using bundled resources. The original review recommendation was based on the method name `downloadAndInstallCorrectVersion()` which is misleading (historical - it used to download but now uses bundled pkg).

### Future Consideration
If network downloads are ever added to the wizard:
1. Use the retry pattern documented below
2. Add to `Sources/KeyPathCore/Utilities/NetworkRetry.swift`

```swift
// Retry utility for future use
func withRetry<T>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 1.0,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?
    var delay = initialDelay
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            if attempt < maxAttempts && isRetryableNetworkError(error) {
                try await Task.sleep(for: .seconds(delay))
                delay *= 2
            }
        }
    }
    throw lastError!
}
```

---

## Task 3: Split WizardTypes.swift (Future)

**Priority:** Low (only when file exceeds 600 lines)
**Effort:** Medium (~1 hour)
**Trigger:** When `WizardTypes.swift` exceeds 600 lines

### Problem
`WizardTypes.swift` is currently 519 lines. As features are added, it may become unwieldy.

### Solution
When the file exceeds 600 lines, split into:
- `WizardPages.swift` - `WizardPage` enum and navigation types
- `WizardIssues.swift` - `WizardIssue`, `IssueIdentifier`, severity/category enums
- `WizardActions.swift` - `AutoFixAction`, requirement types
- `WizardResults.swift` - Detection result types

### Files to Create (when triggered)
- `Sources/KeyPathWizardCore/WizardPages.swift`
- `Sources/KeyPathWizardCore/WizardIssues.swift`
- `Sources/KeyPathWizardCore/WizardActions.swift`
- `Sources/KeyPathWizardCore/WizardResults.swift`

### Acceptance Criteria
- [ ] Each file is focused and under 200 lines
- [ ] All imports updated across codebase
- [ ] No circular dependencies
- [ ] Tests still pass

---

## Task 4: Implement Recipe Ordering (Future)

**Priority:** Low (only if cross-recipe dependencies are added)
**Effort:** Medium (~1-2 hours)
**Trigger:** When recipes need explicit dependency ordering

### Problem
`InstallerEngine.orderRecipes()` is a stub that returns recipes in input order. This works because `ActionDeterminer.determineActions()` already returns actions in the correct order.

### Solution
If cross-recipe dependencies are needed:
1. Add `dependencies: [String]` to `ServiceRecipe` (already exists but unused)
2. Implement Kahn's algorithm for topological sort
3. Detect cycles and throw descriptive error

### Files to Modify
- `Sources/KeyPathAppKit/InstallationWizard/Core/InstallerEngine+Recipes.swift`

### Acceptance Criteria
- [ ] Recipes execute in dependency order
- [ ] Cycle detection with clear error message
- [ ] Test verifies ordering with mock dependencies

---

## Execution Order

1. ✅ **Task 1** (ADR-026 Test) - Already complete, comprehensive tests exist
2. ✅ **Task 2** (Retry Logic) - Not applicable, wizard uses bundled resources (no network)
3. **Task 3** (Split Types) - Defer until triggered by file size (>600 lines)
4. **Task 4** (Recipe Ordering) - Defer until triggered by need

---

## Summary (December 9, 2025)

**All immediate tasks complete:**
- Task 1: Already had 5 comprehensive tests for ADR-026 invariant
- Task 2: Not applicable - wizard has no network downloads (uses bundled pkg)

**Deferred tasks:**
- Task 3 & 4: Future work, triggered by specific conditions

**Conclusion:** The wizard installer codebase is production-ready with no additional work needed.
