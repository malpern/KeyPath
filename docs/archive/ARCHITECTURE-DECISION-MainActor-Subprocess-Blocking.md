# Architecture Decision: MainActor Subprocess Blocking

**Date:** November 26, 2025
**Status:** ✅ Implemented (November 2025)
**Author:** Claude (with direction from @malpern)

## Executive Summary

KeyPath has a recurring UI freeze bug caused by synchronous subprocess calls (`Process().waitUntilExit()`) executing on the MainActor. We've fixed 5+ instances in the last 48 hours using `Task.detached`, but the pattern keeps recurring. This document outlines options for a systematic fix.

## Problem Statement

### Symptom
The wizard UI freezes (spinner stuck, unresponsive) during:
- Clicking "Fix" on Karabiner Driver page
- Post-fix health verification
- Various system state detection operations

### Root Cause
Swift's `@MainActor` isolation combined with synchronous subprocess blocking:

1. Many classes are `@MainActor` (required for SwiftUI integration)
2. These classes call functions that spawn subprocesses (`pgrep`, `launchctl`, etc.)
3. `Process().waitUntilExit()` blocks the actual thread (not cooperative async yielding)
4. Even `async` functions on `@MainActor` block the main thread during subprocess waits
5. Regular `Task { }` inherits actor context, so it still blocks MainActor
6. Only `Task.detached { }` truly runs work off the main thread

### Evidence: Audit Results

```
Total Process() calls in codebase: 85
Total waitUntilExit() calls: 20+

@MainActor classes with Process() calls:
- WizardAutoFixer.swift: 12 calls (HAS @MainActor)
- VHIDDeviceManager.swift: 9 calls
- KarabinerConflictService.swift: 7 calls (HAS @MainActor)
- KanataDaemonManager.swift: 4 calls (HAS @MainActor)
- HelperManager.swift: 4 calls (HAS @MainActor)
- ServiceHealthChecker.swift: 3 calls
- Plus 10+ more files
```

### Evidence: Recent Freeze Fixes (Last 48 Hours)

| Location | Blocking Call | Fix Applied |
|----------|--------------|-------------|
| `WizardKarabinerComponentsPage.swift:440` | `restartServiceWithFallback()` | `Task.detached` |
| `ConfigHotReloadService.swift:164` | `InstallerEngine().checkKanataServiceHealth()` | `Task.detached` |
| `InstallationWizardView.swift:940` | `VHIDDeviceManager().detectConnectionHealth()` | `Task.detached` |
| `ServiceHealthChecker.swift:101,145,284,317` | Various subprocess calls | `Task.detached` |
| `VHIDDeviceManager.swift:121,637` | `pgrep` subprocess | `Task.detached` |

Current `Task.detached` usage: **17 instances** (growing with each fix)

## Options

### Option 1: Continue Whack-a-Mole (Current Approach)

**Description:** Fix each freeze as discovered by wrapping blocking calls in `Task.detached`.

| Criteria | Assessment |
|----------|------------|
| Effort | Low per fix (~5 min), but ongoing indefinitely |
| Risk | High - new freezes will keep appearing |
| Reward | Low - fixes symptoms, not cause |
| Maintainability | Poor - no prevention mechanism |

### Option 2: Mark Blocking APIs as `nonisolated`

**Description:** Make all subprocess-spawning functions `nonisolated`, forcing callers to handle threading.

```swift
// Compiler warns if called directly from @MainActor without await
nonisolated func detectConnectionHealth() async -> Bool {
    let task = Process()
    // ...
}
```

| Criteria | Assessment |
|----------|------------|
| Effort | Medium (2-4 hours to refactor signatures) |
| Risk | Medium - compiler helps but doesn't prevent all issues |
| Reward | Medium - better documentation, some compile-time help |
| Maintainability | Medium - relies on developer discipline |

**Limitation:** Callers can still `await` from MainActor context, which blocks.

### Option 3: Create a Dedicated SubprocessActor

**Description:** Create a custom actor for all subprocess operations. Actor isolation ensures work never runs on MainActor.

```swift
actor SubprocessRunner {
    static let shared = SubprocessRunner()

    func run(_ executable: String, args: [String], timeout: TimeInterval = 30) async throws -> ProcessResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        // ... all Process() calls centralized here
    }

    func pgrep(_ pattern: String) async -> [pid_t] { ... }
    func launchctl(_ args: [String]) async -> LaunchctlResult { ... }
}

// Usage from MainActor code - automatically yields
@MainActor class WizardAutoFixer {
    func fixDriver() async {
        let result = await SubprocessRunner.shared.run("/usr/bin/pgrep", args: ["-f", "kanata"])
        // MainActor yields during subprocess execution
    }
}
```

| Criteria | Assessment |
|----------|------------|
| Effort | Medium-High (4-8 hours) |
| Risk | Low - clear architectural boundary |
| Reward | High - prevents future issues by design |
| Maintainability | High - single point of control |

### Option 4: Background Service Layer

**Description:** Create a non-MainActor service layer for all system operations.

```swift
// Never @MainActor - owns all system interaction
final class SystemOperationsService {
    func checkVHIDHealth() async -> VHIDHealthStatus { ... }
    func checkKanataHealth() async -> KanataHealthStatus { ... }
    func runRepairSequence(_ steps: [RepairStep]) async -> RepairResult { ... }
}

// UI layer - only does UI work
@MainActor class WizardViewModel: ObservableObject {
    @Published var isLoading = false

    func onFixTapped() {
        isLoading = true
        Task {
            let result = await systemOps.performFix(...)  // Yields MainActor
            self.isLoading = false
            self.handleResult(result)
        }
    }
}
```

| Criteria | Assessment |
|----------|------------|
| Effort | High (1-2 days significant refactor) |
| Risk | Medium - large change surface |
| Reward | Very High - clean architecture, testable |
| Maintainability | Very High - clear separation of concerns |

### Option 5: Audit + SubprocessActor Hybrid (Recommended)

**Description:** Combine immediate audit with Option 3's actor pattern.

**Phase 1 (1-2 hours):**
- Audit all `Process()` calls
- Identify which are in @MainActor context
- Prioritize by user-facing impact

**Phase 2 (2-3 hours):**
- Create `SubprocessRunner` actor
- Migrate highest-risk calls first
- Add logging for subprocess duration

**Phase 3 (ongoing):**
- Gradually migrate remaining calls
- Add lint rule or code review checklist item
- Expand test seams (like existing `VHIDDeviceManager.testPIDProvider`)

| Criteria | Assessment |
|----------|------------|
| Effort | Medium (4-6 hours initial, incremental ongoing) |
| Risk | Low - incremental, testable |
| Reward | High - prevents future issues |
| Maintainability | High - clear pattern, single entry point |

## Recommendation

**Option 5 (Audit + SubprocessActor Hybrid)** provides the best balance:

1. **Immediate relief:** Audit identifies remaining problem areas
2. **Architectural fix:** Actor pattern prevents future issues by design
3. **Incremental:** Can migrate files one at a time
4. **Testable:** Actor can be mocked for tests
5. **Observable:** Centralized logging shows subprocess durations

## Implementation ✅

**Location:** `Sources/KeyPathCore/SubprocessRunner.swift`

The `SubprocessRunner` actor has been implemented and all high-priority files have been migrated.

### Canonical Pattern

**✅ DO: Use SubprocessRunner for all subprocess execution**

```swift
// From @MainActor context - automatically yields MainActor during execution
@MainActor class MyService {
    func checkSomething() async {
        // ✅ Correct: Use SubprocessRunner.shared
        let result = try await SubprocessRunner.shared.run(
            "/usr/bin/pgrep",
            args: ["-f", "kanata"],
            timeout: 5
        )
        
        if result.exitCode == 0 {
            // Process stdout
            let output = result.stdout
        }
        
        // ✅ Convenience methods available
        let pids = await SubprocessRunner.shared.pgrep("kanata.*--cfg")
        let launchctlResult = try await SubprocessRunner.shared.launchctl("print", ["system/com.keypath.kanata"])
    }
}
```

**❌ DON'T: Use Process() directly**

```swift
// ❌ Wrong: Blocks MainActor
@MainActor class MyService {
    func checkSomething() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "kanata"]
        try task.run()
        task.waitUntilExit()  // BLOCKS MAIN THREAD
    }
}
```

### Key Features

1. **Actor Isolation:** All subprocess work runs on the actor's executor, never on MainActor
2. **Timeout Support:** Default 30s timeout, configurable per call
3. **Automatic Logging:** Logs execution time, warns on >5s operations
4. **Error Handling:** Throws `SubprocessError` for timeouts and launch failures
5. **Convenience Methods:** `pgrep()` and `launchctl()` helpers for common operations

### Migration Status

**✅ Completed (High Priority):**
- `WizardAutoFixer.swift` - All Process() calls migrated
- `KarabinerConflictService.swift` - All Process() calls migrated
- `KanataDaemonManager.swift` - All Process() calls migrated
- `HelperManager.swift` - All Process() calls migrated
- `ServiceBootstrapper.swift` - All Process() calls migrated
- `KanataBinaryInstaller.swift` - All Process() calls migrated
- `ConfigurationManager.swift` - All Process() calls migrated
- `InstallationCoordinator.swift` - All Process() calls migrated

**Remaining (Lower Priority):**
- `VHIDDeviceManager.swift` - Some Process() calls remain (non-MainActor context)
- `DiagnosticsService.swift` - Some Process() calls remain
- Other utility files - Can be migrated incrementally

## Questions for Senior Engineer

1. **Actor vs DispatchQueue:** Would a simple `DispatchQueue.global()` wrapper be sufficient, or does the actor pattern provide meaningful benefits here?

2. **Timeout handling:** Current subprocess calls have no timeout. Should we add a global timeout (e.g., 30s) with cancellation?

3. **Test seams:** We have `VHIDDeviceManager.testPIDProvider` for mocking. Should we expand this pattern or use the actor's isolation for testing?

4. **Migration strategy:** Should we migrate all 85 `Process()` calls at once, or prioritize the 17 in `@MainActor` classes?

5. **Lint enforcement:** Is there a SwiftLint rule or similar to warn when `Process()` is used outside the actor?

## Appendix: Files Requiring Migration

### High Priority (@MainActor + User-Facing)
- `WizardAutoFixer.swift` - 12 Process() calls
- `KarabinerConflictService.swift` - 7 calls
- `KanataDaemonManager.swift` - 4 calls
- `HelperManager.swift` - 4 calls
- `InstallationWizardView.swift` - indirect via health checks

### Medium Priority (@MainActor)
- `ServiceBootstrapper.swift` - 3 calls
- `KanataBinaryInstaller.swift` - 3 calls
- `ConfigurationManager.swift` - 2 calls
- `InstallationCoordinator.swift` - 2 calls

### Lower Priority (Not @MainActor)
- `VHIDDeviceManager.swift` - 9 calls (some already fixed)
- `DiagnosticsService.swift` - 4 calls
- `ProcessLifecycleManager.swift` - 3 calls
- `PackageManager.swift` - 3 calls
