# Code Quality Cleanup Plan

**Status:** In Progress
**Created:** 2026-05-02
**Goal:** Address remaining code smells a senior Mac developer would flag in review.

## Audit Summary (2026-05-02)

| Category | Count | Status |
|----------|-------|--------|
| `nonisolated(unsafe)` on static constants | 7 | **Done** — removed in Phase 1 |
| God objects (>800 lines) | 5 | **Phase 2 in progress** |
| Singletons (`static let/var shared`) | 94 | ~29 worth injecting (Phase 4) |
| Dead code / stale TODOs | 5 | Healthy — no action needed |
| Untested modules | 5 | KeyPathInstallationWizard most critical |

## Phase 1: Remove unnecessary `nonisolated(unsafe)` ✅

Removed 7 escape hatches across 5 files. Remaining 43 are justified (DI containers, test overrides, lock-guarded caches).

## Phase 2: Extract LiveKeyboardOverlayController ✅

Split 1,360-line controller into 7 focused files. Core file is 753 lines (stored properties + window lifecycle + NSWindowDelegate — splitting further would scatter related logic).

| File | Lines | Responsibility |
|------|-------|----------------|
| `LiveKeyboardOverlayController.swift` | 753 | Core: properties, init, window lifecycle, visibility, frame persistence, NSWindowDelegate |
| `+LayerState.swift` | 139 | Layer change observation, one-shot override, layer name updates |
| `+LauncherSession.swift` | 89 | Launcher layer activation/deactivation, restore-after-action |
| `+KeyClickHandling.swift` | 100 | Key click dispatch, keymap change handling |
| `+AppSuppression.swift` | 24 | Per-app hide/restore |
| `+Observers.swift` | 218 | Notification observers: mapper, wizard, accessibility, health |
| `+Inspector.swift` | 411 | Inspector panel open/close/animate/resize (existing) |

## Phase 3: Extract LiveKeyboardOverlayView (1,126 → ~300)

Large SwiftUI view. Already partially split (+Header, +Inspector, +LauncherWelcome, +RuleManagement). Further extraction:
- **KeyCapGridView** — keyboard grid rendering
- **OverlayToolbarView** — controls, layer picker

**Risk:** Low — SwiftUI views compose naturally.

## Phase 4: Inject high-value singletons (larger effort)

~29 singletons worth converting. Prioritized by call-site count:
1. **PreferencesService** (45 call sites)
2. **PermissionOracle** (30+)
3. **ServiceHealthChecker** (20+)
4. **KanataDaemonManager** (15+)
5. **HelperManager** (10+)

Approach: Existing `ServiceContainer` + `EnvironmentKey` pattern. One service per session.

## Phase 5: Test KeyPathInstallationWizard

17,804 lines, 64 files, zero tests. Highest-risk untested surface.

## Success Criteria

- [x] Zero unnecessary `nonisolated(unsafe)` on static constants
- [x] LiveKeyboardOverlayController.swift split into 7 focused files (core: 753 lines)
- [ ] No source file over 800 lines (except RuntimeCoordinator — separate concern)
- [ ] Top 5 singletons injectable via init or @Environment
- [ ] All tests pass throughout
