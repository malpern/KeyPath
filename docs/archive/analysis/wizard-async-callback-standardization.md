# Wizard Async Callback Standardization

**Status**: Deferred (Low Priority Housekeeping)
**Effort**: Low-Medium
**Risk**: Low

## Problem

Wizard page `onRefresh` callbacks have inconsistent signatures:

| Page | Current Signature |
|------|-------------------|
| `WizardKarabinerComponentsPage` | `() -> Void` (sync) |
| `WizardAccessibilityPage` | `() async -> Void` (async) |
| `WizardInputMonitoringPage` | `() async -> Void` (async) |

This inconsistency:
- Prevents proper async/await propagation
- Makes refresh operations non-cancellable
- Complicates error handling

## Recommended Fix

Standardize all `onRefresh` callbacks to `() async -> Void`.

## Files to Modify

1. **`Sources/KeyPathAppKit/InstallationWizard/UI/Pages/WizardKarabinerComponentsPage.swift`**
   - Line ~20: Change `let onRefresh: () -> Void` to `let onRefresh: () async -> Void`
   - Update any internal usages

2. **`Sources/KeyPathAppKit/InstallationWizard/UI/InstallationWizardView.swift`**
   - Update call sites where `onRefresh` is passed to `WizardKarabinerComponentsPage`

3. **Any other wizard pages with sync callbacks** (verify none exist)

## Implementation Steps

- [ ] Search for all `onRefresh` declarations in wizard pages
- [ ] Change sync signatures to async
- [ ] Update all call sites
- [ ] Verify existing `Task { await onRefresh() }` patterns still work
- [ ] Run tests to verify no regressions

## Why Not Now

This is housekeeping, not a bug fix. Current behavior works, it's just inconsistent. Tackle this when:
- You're already touching wizard pages for another feature
- You have a slow day and want to improve code quality

## Related Context

This was identified during review of task cancellation patterns. The deeper issue (making `restartServiceWithFallback()` cancellation-cooperative) was **deferred indefinitely** due to the risk of leaving services in partial state if cancelled mid-restart.

### Why Cancellation-Cooperative Was Deferred

Making `restartServiceWithFallback()` and its call chain (`ProcessCoordinator`, `InstallerEngine`) cancellation-cooperative would require:

1. Adding `try Task.checkCancellation()` at every async suspension point
2. Deciding what "cancelled mid-restart" means (leave service stopped? restore previous state?)
3. Handling partial state scenarios

The risk of leaving Kanata in a partial state outweighs the benefit of faster wizard dismissal. The current "ghost restart" behavior is bounded by internal timeouts and completes harmlessly in the background.
