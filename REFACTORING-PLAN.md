# KeyPath Refactoring Plan

**Goal:** Prepare codebase for open-source release by eliminating over-engineering, fixing infrastructure, and improving maintainability.

**Timeline:** 6 weeks (Week 1-2 complete)
**Last Updated:** October 25, 2025

---

## 📊 Current State Analysis

### Metrics (Measured on Oct 25, 2025)
- Sources LOC: ~37.9k (wc across `Sources/`)
- Tests LOC: ~7.7k (wc across `Tests/`)
- Total Swift LOC: ~45.6k
- Largest Files (approx.):
  - KanataManager.swift: ~2,788 lines
  - LaunchDaemonInstaller.swift: ~2,465 lines
  - WizardAutoFixer.swift: ~1,197 lines
  - ContentView.swift: ~1,160 lines
- ADRs: 13 (ongoing architectural change)
- Services: Several already exist (ConfigurationService, ServiceHealthMonitor, DiagnosticsService, ProcessLifecycleManager)

### Critical Issues Discovered

#### 🚨 Infrastructure Problems (Highest Priority) ✅ ALL COMPLETE
**Status: Fixed in Phase 0 & 1**

1. **✅ Test runner gives false positives** - FIXED
   - ✅ Added `set -o pipefail` in `run-core-tests.sh`
   - ✅ Fixed non-existent test suite filters (removed `CoreTestSuite`)
   - ✅ Compile errors now properly fail CI
   - **Result: Tests actually run and report correctly**

2. **✅ Linting disabled** - FIXED
   - ✅ Re-enabled `file_length`, `type_body_length`, `function_body_length`
   - ✅ Set generous initial thresholds (file: 1000, type: 600, func: 200)
   - **Result: CI now enforces code quality standards**

3. **✅ Documentation drift** - FIXED
   - ✅ Updated README to Swift 6 (was incorrectly showing 5.9)
   - ✅ Fixed script paths
   - **Result: Documentation matches actual codebase**

4. **✅ Test API drift** - FIXED
   - ✅ Updated `udpClient:` → `tcpClient:` (4 instances)
   - ✅ Removed `setEventRouter()` calls (API removed)
   - ✅ Added missing `vhidVersionMismatch` parameter
   - **Result: All tests compile and run successfully**

#### ⚠️ Code Quality Issues - PENDING (Phases 2-3)
**Status: Scheduled for future phases**

1. **⏳ God object:** KanataManager (2,788 lines) - **Phase 2 (Week 3-4)**
   - Scheduled: Split into ProcessService + ConfigManager + Coordinator
   - Target: <700 lines per file

2. **⏳ UI/Infrastructure coupling** - **Phase 3 (Week 5)**
   - Scheduled: Remove SwiftUI imports from services
   - Add: Error presentation protocols

3. **⏳ Excessive abstraction layers** - **Ongoing evaluation**
   - Will be addressed during Phase 2-3 refactoring

---

## 🎯 Refactoring Phases

### Phase 0: Fix Infrastructure (Week 1) ⚠️ **CRITICAL**

**Goal:** Make CI trustworthy before any refactoring

#### Tasks

##### Fix Test Runner
- [ ] Add `set -o pipefail` to `run-core-tests.sh:7`
  ```bash
  #!/bin/bash
  set -e
  set -o pipefail  # ADD THIS
  ```

- [ ] Replace non-existent suite filters at `run-core-tests.sh:60,70,82`
  ```bash
  # OLD: swift test --filter CoreTestSuite
  # NEW: For Unit:    swift test --filter UnitTestSuite
  #      For Core:    swift test           # run real suites; fail fast on compile errors
  #      Integration: swift test --filter IntegrationTestSuite (opt-in)
  ```

- [ ] Verify failures actually fail
  ```bash
  # Test: introduce intentional failure, confirm exit code != 0
  ```

##### Re-enable Linting
- [ ] Edit `.swiftlint.yml` - remove from `disabled_rules:`
  ```yaml
  # REMOVE these from disabled_rules:
  # - file_length
  # - type_body_length
  # - function_body_length
  ```

- [ ] Set generous initial thresholds
  ```yaml
  file_length:
    warning: 700
    error: 1000
  type_body_length:
    warning: 400
    error: 600
  function_body_length:
    warning: 120
    error: 200
  ```

##### Sync Documentation
- [ ] Update README.md to match Package.swift
  - Swift version: 5.9 → 6
  - macOS target: 14 → 15

- [ ] Fix `Scripts/validate-project.sh` paths
  - `Sources/KeyPath/ContentView.swift` → `Sources/KeyPath/UI/ContentView.swift`

##### Acceptance Criteria
- [ ] Test runner exits non-zero on compile errors
- [ ] Lint rules enabled and CI green (or documented violations)
- [ ] README matches Package.swift reality
- [ ] Scripts reference correct file paths

**Estimated Time:** 2-3 days

---

### Phase 1: Make Tests Pass (Week 2)

**Goal:** Get real test coverage before refactoring

#### Tasks

- [ ] Update tests to current APIs (rename `udpClient:` → `tcpClient:`; remove calls to `setEventRouter`)
- [ ] Skip or gate legacy tests with `#if` or `XCTSkip()` where infra isn’t ready
- [ ] Ensure `swift test` fails on compile errors in CI (runner fixed in Phase 0)
- [ ] Establish baseline coverage from suites that compile (Unit + selected Core)
##### Fix Test API Drift
- [ ] Update `Tests/KeyPathTests/Services/ServiceHealthMonitorTests.swift:30`
  ```swift
  // OLD: udpClient: mockClient
  // NEW: tcpClient: mockClient
  ```

- [ ] Remove `setEventRouter()` calls in `Tests/KeyPathTests/KeyboardCaptureListenOnlyTests.swift:12`
  ```swift
  // API removed - delete calls or mock with protocol
  ```

##### Handle Legacy Tests
- [ ] Add `#if !CI_EXCLUDE_LEGACY` guards or XCTSkip
  ```swift
  func testLegacyUDPFeature() throws {
      #if CI_EXCLUDE_LEGACY
      throw XCTSkip("Legacy UDP test - migrating to TCP")
      #else
      // ... old test
      #endif
  }
  ```

##### Verify Test Coverage
- [ ] Run `swift test` - verify actual tests execute
- [ ] Check test count > 0 in output
- [ ] Ensure meaningful suites run (not 0 tests)

##### Acceptance Criteria
- [ ] All tests compile without errors
- [ ] Tests execute and report real pass/fail
- [ ] No false positives from test runner
- [ ] Baseline coverage established (even if low)

**Estimated Time:** 3-5 days

---

### Phase 2: Split God Objects (Week 3-4)

**Goal:** Reduce file sizes to <700 LOC, improve cohesion

**NOW SAFE TO REFACTOR** - tests will catch regressions

#### Task 1: Split KanataManager (2,788 lines → ~700)

##### Extract ProcessService (~400 LOC)
```swift
// NEW: Sources/KeyPath/Services/ProcessService.swift
class ProcessService {
    func start() async throws -> Bool
    func stop() async throws
    func restart() async throws
    func isHealthy() async -> Bool
    func getPID() async -> pid_t?

    // Move from KanataManager:
    // - launchctl operations
    // - process health checks
    // - restart cooldown logic
}
```

##### Consolidate Configuration Service (~500 LOC)
```swift
// OPTION A (preferred, minimal churn):
// Keep existing Infrastructure service, trim and decouple UI, and fold
// file-watching/backup responsibilities here.
// Path: Sources/KeyPath/Infrastructure/Config/ConfigurationService.swift
// (remove SwiftUI import, remove @MainActor, keep pure I/O)

// OPTION B (rename): Move to Services as a ConfigManager wrapper around a trimmed service.
class ConfigurationManager /* wrapper over ConfigurationService */ {
    func load() async throws -> Config
    func save(_ config: Config) async throws
    func validate(_ config: Config) throws -> ValidationResult
    func startWatching(onChange: @escaping () -> Void)
    func stopWatching()
    func createBackup() throws -> URL
    func restoreBackup(from url: URL) throws
}
```

##### Create Lean KanataCoordinator (~300 LOC)
```swift
// REFACTORED: Sources/KeyPath/Managers/KanataCoordinator.swift
@MainActor
class KanataCoordinator {
    private let processService: ProcessService
    private let configManager: ConfigurationManager

    // Orchestration only:
    func start() async throws
    func stop() async throws
    func reloadConfig() async throws

    // Delegates to services, NO business logic here
}
```

##### Checklist
- [ ] Create ProcessService.swift
- [ ] Consolidate ConfigurationService (or introduce thin ConfigurationManager wrapper)
- [ ] Refactor KanataManager → KanataCoordinator
- [ ] Update all callers to use new services
- [ ] Tests still pass ✅
- [ ] KanataCoordinator <300 LOC
- [ ] Delete or mark old KanataManager deprecated

#### Task 2: Trim ContentView (1,160 → <300 LOC)

##### Extract Subviews
```swift
// NEW: Sources/KeyPath/UI/Components/RecordingPanel.swift (~100 LOC)
struct RecordingPanel: View { ... }

// NEW: Sources/KeyPath/UI/Components/StatusPanel.swift (~80 LOC)
struct StatusPanel: View { ... }

// NEW: Sources/KeyPath/UI/Components/WizardSheetHost.swift (~50 LOC)
struct WizardSheetHost: View { ... }

// REFACTORED: Sources/KeyPath/UI/ContentView.swift (~200 LOC)
struct ContentView: View {
    var body: some View {
        VStack {
            RecordingPanel(...)
            StatusPanel(...)
        }
        .sheet(isPresented: $showWizard) {
            WizardSheetHost(...)
        }
    }
}
```

##### Checklist
- [ ] Extract RecordingPanel
- [ ] Extract StatusPanel
- [ ] Extract WizardSheetHost
- [ ] ContentView <300 LOC
- [ ] UI tests still pass

#### Task 3: Consolidate Wizard (24 files → 6-8)

##### Proposed Structure
```
InstallationWizard/
├── WizardView.swift                    (~300 LOC - main coordinator)
├── WizardState.swift                   (~200 LOC - types, state machine)
├── WizardAutoFixer.swift               (~400 LOC - keep existing, trim if possible)
├── Pages/
│   ├── SummaryPage.swift               (~200 LOC - merge related pages)
│   ├── PermissionsPage.swift           (~250 LOC - all permission screens)
│   ├── ComponentsPage.swift            (~250 LOC - Karabiner + Kanata)
│   └── ServicePage.swift               (~200 LOC - final service setup)
└── Components/
    ├── WizardControls.swift            (~150 LOC - buttons, navigation)
    └── StatusIndicators.swift          (~100 LOC - status cards, icons)
```

##### Checklist
- [ ] Audit existing 24 files
- [ ] Group related pages (3-4 permission pages → 1)
- [ ] Merge small component files
- [ ] Update navigation logic
- [ ] Wizard tests still pass
- [ ] Target: 6-8 files total

##### Acceptance Criteria (Phase 2)
- [ ] No files >700 LOC
- [ ] KanataManager eliminated or <300 LOC
- [ ] ContentView <300 LOC
- [ ] Wizard consolidated to 6-8 files
- [ ] All tests green throughout refactoring
- [ ] Lint warnings addressed

---

## Cross‑Cutting Architecture Criteria (add to all phases)

- Services do not import AppKit/SwiftUI; UI coupling only in Views/ViewModels.
- Non‑UI services are not `@MainActor`; perform I/O off the main thread/actor.
- PermissionOracle uses Apple APIs (`AXIsProcessTrusted`, `IOHIDCheckAccess`); any TCC SQLite probing is behind a feature flag and disabled by default.
- Logging volume budgeted; verbose diagnostics gated behind DEBUG or a runtime flag.

---

## Operational Tasks

- Add a simple metrics script to keep plan numbers honest (e.g., `scripts/metrics.sh` printing LOC and largest files via `wc -l` + `sort -nr`).
- Wire the metrics script into CI summaries and refresh this doc weekly.

**Estimated Time:** 1-2 weeks

---

### Phase 3: Decouple UI from Infrastructure (Week 5)

**Goal:** Separate concerns, remove SwiftUI/AppKit from non-UI code

#### Tasks

##### Remove UI Imports from Services
- [ ] Audit all `Sources/KeyPath/Infrastructure/**/*.swift`
- [ ] Audit all `Sources/KeyPath/Services/**/*.swift`
- [ ] Remove unnecessary `import SwiftUI` / `import AppKit`

##### Example: ConfigurationService
```swift
// BEFORE: Sources/KeyPath/Infrastructure/Config/ConfigurationService.swift
import SwiftUI  // ❌ Why does config service need UI?

// AFTER:
// Remove SwiftUI import

// If needed for errors, use protocol:
protocol ConfigurationErrorPresenting {
    func showError(_ error: ConfigError)
}
// UI layer implements this
```

##### Add Protocols for UI Interactions
```swift
// NEW: Sources/KeyPath/Core/Contracts/ErrorPresenting.swift
protocol ErrorPresenting {
    func showError(title: String, message: String)
    func showWarning(title: String, message: String)
}

// Services depend on protocol, UI implements
```

##### Fix UI Behavior Issues
- [ ] Fix background launch issue in App.swift:230-279
```swift
// BEFORE: App launches in background, requires clicking dock icon
func applicationDidFinishLaunching(_ notification: Notification) {
    // ... setup code ...
}

// AFTER: App activates on launch
func applicationDidFinishLaunching(_ notification: Notification) {
    // ... setup code ...
    NSApplication.shared.activate(ignoringOtherApps: true)
}
```

##### Checklist
- [ ] Remove SwiftUI from ConfigurationService
- [ ] Remove AppKit from non-UI Infrastructure files
- [ ] Create error presentation protocols
- [ ] Update services to use protocols
- [ ] Fix background launch issue (add activate call)
- [ ] Tests pass (may need mock presenters)

##### Acceptance Criteria
- [ ] No `import SwiftUI` in Infrastructure/
- [ ] No `import AppKit` in Services/ (unless truly needed)
- [ ] Clear separation: UI → Coordinator → Services → System
- [ ] Build succeeds, tests green

**Estimated Time:** 3-5 days

---

### Phase 4: Increase Test Coverage (Week 6)

**Goal:** Achieve >50% coverage on critical paths before declaring refactor complete

#### Priority Test Areas

##### 1. KanataCoordinator/ProcessService
```swift
// Tests/KeyPathTests/Services/ProcessServiceTests.swift
func testStartServiceSuccess()
func testStartServiceFailure()
func testRestartWithCooldown()
func testHealthCheckAccurate()
func testPIDTracking()
```
**Target:** 15-20 tests, cover lifecycle edge cases

##### 2. ConfigurationManager
```swift
// Tests/KeyPathTests/Services/ConfigurationManagerTests.swift
func testLoadValidConfig()
func testLoadCorruptedConfig()
func testSaveAtomicWrite()
func testBackupCreation()
func testRestoreFromBackup()
func testFileWatcherTriggersReload()
```
**Target:** 10-15 tests, cover I/O error paths

##### 3. PermissionOracle (Simplified)
```swift
// Tests/KeyPathTests/Services/PermissionOracleTests.swift
func testAppleAPIGrantedReturnsGranted()
func testAppleAPIDeniedReturnsDenied()
func testUnknownShowsUIGuidance()
func testNoTCCDatabaseAccess() // Verify removal
```
**Target:** 8-10 tests, verify simplification worked

##### 4. Installation Wizard Flow
```swift
// Tests/KeyPathTests/Wizard/WizardFlowTests.swift
func testWizardNavigationHappyPath()
func testWizardHandlesMissingPermissions()
func testWizardHandlesKarabinerConflict()
func testAutoFixerActuallyFixes() // Integration test
```
**Target:** 5-8 integration tests

#### Coverage Tools
```bash
# Generate coverage report
swift test --enable-code-coverage

# View report
xcrun llvm-cov report \
  .build/debug/KeyPathPackageTests.xctest/Contents/MacOS/KeyPathPackageTests \
  -instr-profile=.build/debug/codecov/default.profdata

# Target: >50% on critical paths
```

#### Checklist
- [ ] ProcessService: 15-20 tests
- [ ] ConfigurationManager: 10-15 tests
- [ ] PermissionOracle: 8-10 tests
- [ ] Wizard flow: 5-8 integration tests
- [ ] Overall coverage >50%
- [ ] All tests green
- [ ] CI enforces test passing

**Estimated Time:** 5-7 days

---

## 🎯 Success Metrics

### Before Open Source Release

#### Code Quality
- [ ] No files >700 LOC
- [ ] No type bodies >400 LOC
- [ ] No functions >120 LOC
- [ ] Lint rules enabled and green
- [ ] Max abstraction depth: 3 layers (UI → Coordinator → Service)

#### Testing
- [ ] Test coverage >50% on critical paths
- [ ] All tests compile and pass
- [ ] CI fails on test failures (no false positives)
- [ ] Integration tests cover wizard flow

#### Documentation
- [ ] README matches Package.swift
- [ ] ADRs updated with refactoring decisions
- [ ] Scripts reference correct paths
- [ ] Contributing guide added

#### Architecture
- [ ] KanataManager eliminated or <300 LOC
- [ ] Clear service boundaries (Process, Config, Permissions)
- [ ] UI decoupled from Infrastructure
- [ ] PermissionOracle simplified (no TCC database)

---

## 📋 Quick Wins (1-2 Days)

Do these FIRST for immediate impact:

- [ ] Add `set -o pipefail` to `run-core-tests.sh:7`
- [ ] Fix test suite filters (remove `CoreTestSuite`)
- [ ] Update README Swift version (5.9 → 6)
- [ ] Remove SwiftUI import from ConfigurationService
- [ ] Re-enable file_length lint rule

---

## ⚠️ What NOT to Do

**Feature Freeze** - No new features during refactoring period

- ❌ Don't add new wizard pages
- ❌ Don't add new auto-fix capabilities
- ❌ Don't add new service classes
- ❌ Don't create new abstraction layers
- ✅ Do fix bugs
- ✅ Do improve existing code clarity
- ✅ Do add tests for existing features

---

## 📊 Progress Tracking

### Week 1: Infrastructure ✅ COMPLETE
- [x] Test runner fixed (pipefail + filters)
- [x] Linting re-enabled
- [x] Documentation synced
- [x] Scripts updated

### Week 2: Test Reality ✅ COMPLETE
- [x] Tests compile
- [x] Tests run and report accurately
- [x] Legacy tests handled
- [x] Baseline coverage established

### Week 3-4: Core Refactoring
- [ ] KanataManager → ProcessService + ConfigManager + Coordinator
- [ ] ContentView trimmed to <300 LOC
- [ ] Wizard consolidated (24 → 6-8 files)
- [ ] All files <700 LOC

### Week 5: Decoupling
- [ ] UI imports removed from Infrastructure
- [ ] Error presentation protocols added

### Week 6: Test Coverage
- [ ] Critical path tests added
- [ ] Coverage >50%
- [ ] CI enforces quality gates

---

## 🔄 Iteration Strategy

After each phase:
1. Run full test suite
2. Run linter
3. Build release binary
4. Manual smoke test
5. Commit with clear message
6. Update this document

**Roll back if:**
- Tests fail unexpectedly
- Build breaks
- Core functionality regresses

**Keep separate branches for:**
- Each major file split
- Each phase
- Merge to main only when phase complete

---

## 📚 References

- Original evaluation: See initial engineering review
- Detailed evaluation: See second engineering review
- ADRs: See docs/architecture/
- Test strategy: ADR-011 (Test Performance)
- MVVM pattern: ADR-009 (Service Extraction)

---

## 💭 Future Discussion

These topics are deferred for later consideration, after Phase 4 is complete:

### Permission Detection Simplification

**Current State:** PermissionOracle uses a 3-tier hierarchy:
1. Apple APIs (IOHIDCheckAccess)
2. SQLite TCC database reads
3. TCP functional checks
4. netstat port scanning

**Proposed Simplification:** Use only Apple APIs, remove TCC database and inference logic

**Status:** Deferred - Current implementation works reliably. Simplification would need careful evaluation to ensure no regression in permission detection edge cases.

**Considerations:**
- Current approach handles edge cases that pure Apple API might miss
- TCC database fallback helps with wizard scenarios
- Would reduce code from ~410 lines to ~200 lines
- Need to verify System Settings guidance is sufficient replacement

### Product Scope Evaluation ("40% MVP Bloat")

**Question:** Does the current feature set exceed what's necessary for a minimum viable product?

**Status:** Philosophical question about product scope, not a technical issue

**Considerations:**
- Many features were added based on real user needs discovered during development
- "Bloat" depends on target audience - power users vs. casual users
- Some "extra" features enable the core value proposition (auto-fix wizard, diagnostics)
- Should be evaluated after refactoring is complete, when code is cleaner

**Future Action:** Revisit after Phase 4 completion, when architecture is clean and we can objectively evaluate feature value vs. maintenance cost.

---

## 🎓 Lessons Learned

Record here as refactoring progresses:

- Infrastructure must be trustworthy before refactoring
- Test runner false positives are worse than no tests
- Disabled linting enables bad patterns
- God objects grow when guards are removed
- TCC database reads are fragile - use Apple APIs
- UI coupling increases maintenance burden

---

**Last Updated:** October 25, 2025
**Status:** Phase 0 & 1 Complete ✅
**Next Action:** Phase 2 - Split God Objects (KanataManager, ContentView, Wizard)
