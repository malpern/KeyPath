# MainActor Subprocess Migration Plan

**Status:** In Progress (28 → 19 remaining)
**Created:** 2026-05-02
**Goal:** Move all `Process()` calls off `@MainActor` to prevent UI freezes.

## Problem

`Process().waitUntilExit()` blocks the actual thread — not cooperative async yielding. When called on `@MainActor`, the UI freezes for the duration of the subprocess (10-30+ seconds under load for `launchctl`, `pgrep`, etc.).

## Current State

**52 total `Process()` calls** across the codebase:
- **19 in `@MainActor` files** (UI-blocking — 9 migrated, 19 remaining)
- **24 in non-`@MainActor` files** (safe — no migration needed)

### Completed
- ✅ VHIDDeviceManager (pgrep with timeout)
- ✅ ServiceLifecycleCoordinator (launchctl kickstart, pgrep orphan kill)
- ✅ HelperMaintenance (launchctl bootout)
- ✅ SystemValidator (pgrep karabiner_grabber)
- ✅ ProcessLifecycleManager (pgrep -fl kanata)
- ✅ UninstallCoordinator (tccutil, defaults delete)
- ✅ KanataViewModel (defaults write fnState)

## Migration Strategy

Replace `Process()` calls in `@MainActor` files with `SubprocessRunner` (which runs off the main actor). `SubprocessRunner` already exists in KeyPathCore — the migration is mechanical.

Pattern:
```swift
// Before (blocks MainActor):
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
process.arguments = ["-x", "kanata"]
try process.run()
process.waitUntilExit()

// After (runs off MainActor):
let result = try await SubprocessRunner.shared.run("/usr/bin/pgrep", arguments: ["-x", "kanata"])
```

## Priority 1 — High Impact (frequent operations, user-visible freezes)

These files run subprocesses during normal wizard/settings operations:

| File | Calls | What it does | Risk |
|------|-------|-------------|------|
| `VHIDDeviceManager.swift` | 4 | Driver detection (already partially migrated — uses SubprocessRunner for 8 calls) | Low |
| `ServiceLifecycleCoordinator.swift` | 2 | Start/stop kanata via launchctl | Medium |
| `HelperMaintenance.swift` | 2 | Helper repair/diagnosis | Low |
| `SystemValidator.swift` | 1 | System validation during wizard refresh | Medium |
| `KanataDaemonManager.swift` | 1 | Daemon state queries (already partially migrated) | Low |

## Priority 2 — Medium Impact (less frequent but still blocking)

| File | Calls | What it does | Risk |
|------|-------|-------------|------|
| `ProcessLifecycleManager.swift` | 3 | pgrep/pkill for process management | Medium |
| `ActionDispatcher.swift` | 2 | Open files in editor (user-triggered) | Low |
| `UninstallCoordinator.swift` | 2 | Uninstall cleanup | Low |
| `SignatureHealthCheck.swift` | 2 | Code signature verification | Low |
| `RuntimeCoordinator.swift` | 1 | Runtime orchestration | Medium |
| `KanataViewModel.swift` | 1 | View model subprocess call | Low |

## Priority 3 — Low Impact (rare operations)

| File | Calls | What it does | Risk |
|------|-------|-------------|------|
| `WizardPermissionFinderHelper.swift` | 2 | Open System Settings | Low |
| `PluginManager.swift` | 1 | Plugin loading | Low |
| `SettingsView+General.swift` | 1 | Settings UI action | Low |
| `AppRestarter.swift` | 1 | App restart | Low |
| `App.swift` | 1 | App launch | Low |
| `WizardServiceProtocols.swift` | 1 | Protocol default impl | Low |

## No Migration Needed (not on MainActor)

These 17 files (24 calls) run off the main actor already:
`SubprocessRunner.swift`, `PrivilegedExecutor.swift`, `PrivilegedCommandRunner.swift`,
`ExternalKanataService.swift`, `LauncherService.swift`, `WizardSystemPaths.swift`,
`SimulatorService.swift`, `ProcessKiller.swift`, `PermissionOracle.swift`,
`HelperService.swift`, `DeviceEnumerationService.swift`, `BlessDiagnostics.swift`,
`PIDFileManager.swift`, `LaunchDaemonPIDCache.swift`, `LayoutAnalysisRunner.swift`,
`SimpleLogViewer.swift`, `WizardKanataMigrationPage.swift`

## Execution Approach

Each file is an independent migration:
1. Read the `Process()` call and understand what it does
2. Replace with `SubprocessRunner.shared.run()` (or `.runForOutput()`)
3. Handle the now-async return with `await`
4. Run tests
5. Commit

Can be done 3-5 files per session. Priority 1 files first — they cause the actual freezes users see.

## Success Criteria

- Zero `Process()` calls in `@MainActor` files
- All 413+ tests pass
- No UI freezes during wizard operations
