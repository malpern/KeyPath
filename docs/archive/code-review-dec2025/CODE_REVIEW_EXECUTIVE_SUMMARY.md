# KeyPath Code Review - Executive Summary

**Date:** December 5, 2025
**Reviewer:** Claude Code
**Codebase Size:** ~41,000 lines (excluding tests)

---

## Overall Assessment: ⚠️ Moderate Technical Debt

The KeyPath codebase demonstrates a mix of well-architected components (InstallerEngine façade, PermissionOracle) alongside significant technical debt from organic growth. The core functionality is solid, but maintainability is at risk without targeted refactoring.

---

## Top 5 Critical Issues

### 1. 🔴 God Classes (3 files need immediate extraction)

| File | Lines | Problem |
|------|-------|---------|
| `RulesSummaryView.swift` | 2,048 | 12 embedded structs, mixed concerns |
| `InstallationWizardView.swift` | 1,774 | 40+ @State properties |
| `RuntimeCoordinator.swift` | 1,297 | Fragmented extensions, overlap |

**Impact:** Hard to test, modify, or debug. New developers struggle to understand.

**Fix:** Extract ViewModels and split into focused files (8-12 hours total).

---

### 2. 🔴 Unnecessary Abstraction Layers

```
KanataService → ProcessCoordinator → RuntimeCoordinator → ProcessManager
```

Four layers for process management when two would suffice. `ProcessCoordinator` (124 lines) does nothing but delegate.

**Impact:** Cognitive overhead, harder debugging, slower development.

**Fix:** Remove `ProcessCoordinator`, simplify to 2 layers (4-6 hours).

---

### 3. 🟠 TCP Client Monolith

`KanataTCPClient.swift` (1,215 lines) handles:
- Connection lifecycle
- Protocol parsing
- Command execution
- Reconnection logic

**Impact:** Can't test protocol parsing without TCP connection. Hard to extend.

**Fix:** Extract `TCPConnection`, `KanataProtocol`, `KanataCommandExecutor` (6-8 hours).

---

### 4. 🟠 Test Seams via Unsafe Statics

Multiple components use `nonisolated(unsafe) static var testXXX` instead of proper dependency injection.

```swift
// Current pattern (problematic)
nonisolated(unsafe) static var testPIDProvider: (() -> [Int32])?

// Better pattern
protocol PIDProviding { func getPIDs() -> [Int32] }
```

**Impact:** Potential test pollution, harder to reason about, compiler can't help.

**Fix:** Migrate to protocol-based DI for major components (gradual, per-component).

---

### 5. 🟡 Swift Concurrency Issues

- 8+ uses of `@unchecked Sendable` (masks potential data races)
- Timer-based delays instead of `Task.sleep(for:)`
- Mixed `DispatchQueue.main.async` and `@MainActor`

**Impact:** Potential runtime crashes, harder to maintain as Swift evolves.

**Fix:** Audit and modernize async patterns (gradual, ongoing).

---

## What's Working Well

✅ **InstallerEngine façade** - Clean separation of installation logic
✅ **PermissionOracle** - Single source of truth for permissions
✅ **ADR documentation** - Excellent architectural decision records
✅ **Test infrastructure** - `KeyPathTestCase` base class, test seams exist
✅ **WizardDesignSystem** - Cohesive UI design tokens
✅ **KanataDaemonManager** - Cleanest manager implementation

---

## Effort Estimates

| Priority | Task | Hours |
|----------|------|-------|
| P1 | Extract InstallationWizardView state | 4-6 |
| P1 | Split RulesSummaryView | 3-4 |
| P1 | Fix ConfigFileWatcher atomic write bug | 1-2 |
| P2 | Extract KanataTCPClient | 6-8 |
| P2 | Collapse process layers | 4-6 |
| P2 | Create shared ToastManager | 2-3 |

**Immediate (P1):** 8-12 hours
**Short-term (P2):** 12-17 hours
**Total:** 40-60 hours for significant improvement

---

## Recommendations

### Do First (This Week)

1. **Extract `WizardViewModel`** from `InstallationWizardView`
   - Move 40+ @State properties to @StateObject ViewModel
   - Immediately improves testability

2. **Fix the atomic write bug** in `ConfigFileWatcher`
   - `pendingAtomicWriteEvent` not cleared in all paths
   - Could cause missed config reloads

### Do Soon (This Month)

3. **Delete `ProcessCoordinator.swift`** - pure pass-through layer
4. **Extract TCP responsibilities** - connection vs protocol vs commands
5. **Consolidate toast implementations** - 4+ duplicates across UI

### Track for Later

6. Audit `@unchecked Sendable` usage
7. Replace Timer patterns with Task.sleep
8. Consider module extraction for TCP and Rules subsystems

---

## Risk Assessment

| Area | Current Risk | After P1 Fixes |
|------|--------------|----------------|
| Adding new wizard steps | 🔴 High | 🟢 Low |
| TCP protocol changes | 🟠 Medium | 🟢 Low |
| New rule types | 🟠 Medium | 🟡 Low-Med |
| Concurrency bugs | 🟡 Low-Med | 🟡 Low-Med |
| Test reliability | 🟡 Low-Med | 🟢 Low |

---

## Conclusion

KeyPath is a **functional, feature-complete application** with good architectural patterns in its core infrastructure. The technical debt is concentrated in a few large files that grew organically. Targeted refactoring of the top 3 God classes would dramatically improve maintainability with modest effort (8-12 hours).

The codebase is **not in crisis** but is approaching a tipping point where changes become increasingly risky. Investing in the recommended refactoring now will pay dividends in development velocity and bug reduction.

---

*Full detailed report: [CODE_REVIEW_REPORT.md](./CODE_REVIEW_REPORT.md)*
