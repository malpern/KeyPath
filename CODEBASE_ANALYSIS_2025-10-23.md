# KeyPath Codebase Analysis: Organizational Issues & Over-Engineering

**Date:** October 23, 2025
**Scope:** Medium-depth analysis (files, duplication, organizational patterns)
**Codebase Size:** 39,302 lines across 120 Swift files

---

## Executive Summary

The KeyPath codebase shows **strong fundamentals but significant organizational issues** that will hinder new contributor adoption. While the architecture is sound in principle, execution has created:

1. **One massive "god object"** that must be broken up
2. **Duplicate logging & utility infrastructure**
3. **Unused/over-abstracted protocol interfaces**
4. **Fragmented permission checking logic**
5. **Large UI views that mix concerns**
6. **Installation wizard with complex state management**

**Overall Grade:** 6/10 for maintainability (improved from 5/10 last review, but still significant issues)

---

## Critical Issues (Block Contributions)

### 1. KanataManager is Still a God Object (2,820 lines)

**File:** `/Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/Sources/KeyPath/Managers/KanataManager.swift`

**Problem:** Despite previous refactoring efforts (extracting 599 lines to KarabinerConflictService), the manager is still absurdly large and handles 10+ distinct responsibilities:

**Confirmed Responsibilities:**
```
1. Process lifecycle management        (startKanata, stopKanata, etc.)
2. Configuration management           (saveConfiguration, loadConfiguration)
3. Service coordination               (ServiceHealthMonitor delegation)
4. UDP communication                  (KanataUDPClient delegation)
5. Health monitoring                  (updateStatus, retryAfterFix)
6. Diagnostics                        (getSystemDiagnostics, diagnoseKanataFailure)
7. State management                   (currentState, errorReason, etc. - 30+ @Published properties)
8. Permission checking                (hasInputMonitoringPermission, hasAccessibilityPermission)
9. File watching                      (startConfigFileWatching, stopConfigFileWatching)
10. Backup management                 (createPreEditBackup, getAvailableBackups)
11. Wizard integration                (showWizardForInputMonitoring, onWizardClosed)
12. Karabiner integration             (Methods delegated to KarabinerConflictService)
```

**Metrics:**
- **Line count:** 2,820 (was 2,828, minimal progress)
- **Method count:** ~60+ public methods
- **Published properties:** 30+
- **State enum values:** Complex multi-state machine

**Code Examples of Mixing Concerns:**

```swift
// Lines 322-338: File watching (should be in ConfigFileWatcher)
func startConfigFileWatching() {
    configFileWatcher = ConfigFileWatcher(paths: [configPath]) { [weak self] in
        Task { @MainActor in
            self?.lastConfigUpdate = Date()
            // ...
        }
    }
}

// Lines 520-542: Diagnostics (should be in DiagnosticsService)
func diagnoseKanataFailure(_ exitCode: Int32, _ output: String) {
    // Complex diagnostics logic
}

// Lines 1683-1691: Permission checking (should delegate to Oracle)
func hasInputMonitoringPermission() async -> Bool {
    let snapshot = await PermissionOracle.shared.currentSnapshot()
    return snapshot.keyPath.inputMonitoring.isReady
}

// Lines 1751-1776: Settings integration (should be separate)
func openInputMonitoringSettings() {
    // Open system preferences logic...
}
```

**Impact on Contributors:**
- New developer wants to fix a bug in "config saving"
- Opens KanataManager
- Sees 2,820 lines
- Can't find where config actually saves (it's delegated)
- Gives up

**What Needs to Happen:**
Extract into focused coordinators:
- `ProcessLifecycleCoordinator` - Kanata startup/shutdown/restart (500 lines)
- `DiagnosticsCoordinator` - Failure diagnosis & recovery (400 lines)
- `PermissionCheckingCoordinator` - Permission validation (200 lines)
- `ServiceCoordinator` - Health checks & retries (300 lines)
- `KanataManager` - Becomes thin orchestrator (800 lines max)

---

### 2. Duplicate & Over-Abstracted Protocol Interfaces (Dead Code)

**Location:** `/Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/Sources/KeyPath/Core/Contracts/`

**Problem:** Multiple protocol files with no actual implementations or uses

**Confirmed Unused Protocols:**
1. **PermissionChecking.swift** (275 lines)
   - Defines entire protocol hierarchy
   - Used: **0 times** in the codebase
   - Has 2 implementations (PermissionSet, SystemPermissionSnapshot) that are never instantiated

2. **EventTapping.swift** (139 lines)
   - Used: ~3 times (minimal use)
   - Provides: Abstract event tapping capabilities
   - Reality: Only KeyboardCapture implements it

3. **EventProcessing.swift** (157 lines)
   - Used: ~5 times
   - Provides: Event processing pipeline
   - Reality: Complexity > value provided

4. **OutputSynthesizing.swift** (263 lines)
   - Used: ~7 times
   - Provides: Event synthesis capabilities
   - Reality: Very simple use cases

5. **ConfigurationProviding.swift** (173 lines)
   - Used: ~2 times
   - Provides: Configuration interface
   - Reality: ConfigurationService already provides this

**Evidence of Non-Use:**

```swift
// File: PermissionChecking.swift (275 lines of protocol definitions)
protocol PermissionChecking {
    func checkPermission(_ type: SystemPermissionType, for subject: PermissionSubject) async -> PermissionStatus
    func checkPermissions(_ types: [SystemPermissionType], for subject: PermissionSubject) async -> PermissionSet
    func getSystemSnapshot() async -> SystemPermissionSnapshot
}

// Search result: This protocol is NEVER implemented anywhere in the codebase
// The PermissionOracle uses a different internal architecture
```

**Impact:**
- Adds 1,000+ lines of unused abstraction
- Creates "interface debt" (would need updates if code changed)
- Confuses new contributors ("which permission interface should I use?")
- Suggests unfinished refactoring

---

### 3. Duplicate Logging Infrastructure

**Files Involved:**
1. `/Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/Utilities/Logger.swift` (AppLogger)
2. `/Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/InstallationWizard/Core/WizardLogger.swift` (WizardLogger)
3. `/Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/Core/Contracts/Logging.swift` (Protocol)

**Problem:** Two independent logging systems with almost identical functionality

**WizardLogger (46 lines):**
```swift
@MainActor
class WizardLogger {
    static let shared = WizardLogger()
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    
    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        print(logEntry.trimmingCharacters(...))
        // Write to file
    }
}
```

**What's Wrong:**
- Hardcoded log path: `/Volumes/FlashGordon/Dropbox/code/KeyPath/logs/wizard-restart.log`
- This is a **developer's personal path**, not production-safe
- Duplicate of AppLogger functionality
- Only used in WizardLogger.swift itself (no imports)

**AppLogger vs WizardLogger:**
- Both: Singleton pattern
- Both: Date formatting with timestamps
- Both: Write to file + console
- Difference: Separate log files, separate instances
- Result: Maintenance burden (fixes needed in 2 places)

---

## High-Priority Issues (Affects Code Quality)

### 4. Fragmented Permission Checking Logic

**Files with Permission Logic:**
1. `PermissionOracle.swift` (671 lines) - **Single source of truth**
2. `PermissionService.swift` (79 lines) - **Legacy stubs** (mostly deprecated)
3. `KanataManager.swift` - Has `hasInputMonitoringPermission()`, `hasAccessibilityPermission()`
4. `HelpSheets.swift` (615 lines) - Shows permission status in UI
5. `PermissionCard.swift` (162 lines) - UI component with permission logic
6. `PermissionChecking.swift` (275 lines) - **Unused protocol interface**

**Duplication Examples:**

Permission check #1 (KanataManager):
```swift
// KanataManager.swift:1683
func hasInputMonitoringPermission() async -> Bool {
    let snapshot = await PermissionOracle.shared.currentSnapshot()
    return snapshot.keyPath.inputMonitoring.isReady
}
```

Permission check #2 (HelpSheets.swift):
```swift
// HelpSheets.swift (similar logic in multiple places)
let snapshot = await PermissionOracle.shared.currentSnapshot()
if snapshot.keyPath.inputMonitoring.isReady { /* show green */ }
```

**Problem:** Multiple UI components call Oracle directly instead of using manager API

**Recommendation:** Create single permission facade:
```swift
// In KanataManager
func getPermissionStatus() async -> PermissionStatus {
    let snapshot = await PermissionOracle.shared.currentSnapshot()
    return PermissionStatus(from: snapshot)
}
```

---

### 5. Large, Mixed-Concern UI Views

**SettingsView.swift** (1,351 lines)
- Manages user preferences
- Handles app launch settings
- Controls LaunchAgent installation
- Manages Karabiner integration settings
- Contains 10+ sub-views inline

**ContentView.swift** (1,101 lines)
- Main app interface
- Handles keyboard recording
- Permission status display
- Service state management
- Wizard presentation logic
- Contains multiple sub-views inline

**DiagnosticsView.swift** (999 lines)
- System diagnostics display
- Log analysis
- System information
- Health check results
- Multiple view hierarchies inline

**Problem:** Each view has 3+ responsibilities and mixes UI with business logic

**Example from ContentView:**
```swift
// Lines ~200-300: Recording UI
VStack { /* KeyRecording UI */ }

// Lines ~300-400: Status display
VStack { /* Status messages */ }

// Lines ~400-500: Permission checks
.task {
    while true {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        updateUI(from: snapshot)  // Tight coupling to Oracle
    }
}

// Lines ~500-600: Wizard presentation
.sheet(isPresented: $showWizard) {
    InstallationWizardView(...)
}
```

**Recommendation:** Extract sub-views to separate files
- `RecordingSection.swift` - Keyboard recording UI
- `StatusSection.swift` - Status display
- `PermissionSection.swift` - Permission checks
- ContentView becomes: 200 lines max (composition only)

---

### 6. Installation Wizard: 44 Files, 17,441 Lines

**Structure Issues:**

```
InstallationWizard/ (17,441 lines across 44 files)
├── Core/ (11 files, heavy)
│   ├── WizardStateMachine.swift (248 lines)
│   ├── WizardStateManager.swift (33 lines)
│   ├── WizardStateInterpreter.swift (245 lines)
│   ├── WizardNavigationEngine.swift (352 lines)
│   ├── WizardNavigationCoordinator.swift (117 lines)
│   └── WizardAsyncOperationManager.swift (591 lines) ⚠️ LARGE
│   └── LaunchDaemonInstaller.swift (2,465 lines) ⚠️ CRITICAL
│   └── PackageManager.swift (650 lines) ⚠️ LARGE
│   └── WizardAutoFixer.swift (1,105 lines) ⚠️ LARGE
│
├── UI/ (20+ files, mixed concerns)
│   ├── Pages/ (12 pages with similar structure)
│   ├── Components/ (8+ components)
│   └── WizardDesignSystem.swift (955 lines) ⚠️ MONOLITHIC
│
└── Components/ (StatusIndicators, PermissionCard, HelpSheets)
```

**Specific Problems:**

**LaunchDaemonInstaller.swift** (2,465 lines)
```
Functions/Methods: 40+
Responsibilities:
1. Plist file generation (generateKanataPlist, generateVHIDDaemonPlist, generateVHIDManagerPlist)
2. Service installation (createAllLaunchDaemonServices, createKanataLaunchDaemon, etc.)
3. Service loading/unloading (loadService, unloadService, removeAllServices)
4. Health checks (isServiceHealthy, isServiceLoaded, getServiceStatus)
5. Diagnostics (diagnoseServiceFailures, analyzeServiceStatus, analyzeKanataLogs)
6. Repair/recovery (restartUnhealthyServices, repairVHIDDaemonServices)
7. Configuration (regenerateServiceWithCurrentSettings, isServiceConfigurationCurrent)
8. Admin privilege management (executeWithAdminPrivileges, executeConsolidatedInstallation)
9. Log rotation (installLogRotationService, rotateCurrentLogs)
10. Binary installation (installBundledKanataBinaryOnly)
```

This should be split into:
- `LaunchDaemonManager` (300 lines) - Service lifecycle
- `LaunchDaemonHealthChecker` (200 lines) - Health monitoring
- `LaunchDaemonRepair` (200 lines) - Recovery logic
- `PlistGenerator` (200 lines) - Config generation

**WizardDesignSystem.swift** (955 lines)
```
Contains:
- View extensions (.wizardCard(), .wizardBackground())
- Colors struct (50+ named colors)
- Typography (12+ font definitions)
- Spacing constants (15+ spacing values)
- Modifiers (15+ custom modifiers)
```

Should be split into:
- `WizardColors.swift` (100 lines)
- `WizardTypography.swift` (50 lines)
- `WizardSpacing.swift` (30 lines)
- `WizardModifiers.swift` (200 lines)
- `WizardDesignSystem.swift` (100 lines - coordinator)

**Navigation State Duplication:**
- WizardStateMachine (248 lines) - State definitions
- WizardStateManager (33 lines) - State holder
- WizardStateInterpreter (245 lines) - State logic
- WizardNavigationEngine (352 lines) - Navigation rules
- WizardNavigationCoordinator (117 lines) - Coordination logic

That's **5 files** for navigation logic that could be 2:
- `WizardState.swift` (200 lines) - State enum + interpretation
- `WizardNavigator.swift` (200 lines) - Navigation rules

---

## Medium-Priority Issues (Technical Debt)

### 7. Redundant Legacy Code & Stubs

**PermissionService.swift** (79 lines, mostly deprecated):
```swift
/// Legacy compatibility flag for TCC access
static var lastTCCAuthorizationDenied = false

/// Legacy method stub - functionality moved to Oracle
func clearCache() {
    AppLogger.shared.log("🔮 [PermissionService] clearCache() called - Oracle handles caching now")
}

/// Legacy method stub - opens Input Monitoring settings
static func openInputMonitoringSettings() { ... }

/// Legacy method stub - functionality moved to Oracle
func markInputMonitoringPermissionGranted() { ... }
```

**Impact:** 
- Maintains 6+ deprecated methods as "stubs"
- No callers (verified via grep)
- Takes maintenance burden
- Confuses developers about which API to use

**Deprecated Error Types:**
```swift
// KanataManager.swift:18
@available(*, deprecated, message: "Use KeyPathError.configuration(...) instead")

// ProcessLifecycleManager.swift:15
@available(*, deprecated, message: "Use KeyPathError.process(...) instead")

// KanataConfigManager.swift:14
enum KanataConfigManagerError: Error { ... }  // Never used

// RecordingCoordinator.swift:100
enum RecordingFailureReason { ... }  // Deprecated enum
```

**Recommendation:** Remove all deprecated stubs and old error types in one cleanup pass

---

### 8. Configuration System Fragmentation

**Files involved in config operations:**
1. `ConfigurationService.swift` (842 lines) - File operations
2. `KanataConfigGenerator.swift` (305 lines) - Config generation
3. `ConfigBackupManager.swift` (241 lines) - Backup/restore
4. `KanataConfigManager.swift` (524 lines) - Config validation & management
5. `ConfigFileWatcher.swift` (496 lines) - File change detection
6. `KanataManager.swift` - Coordination layer

**Multiple APIs for same operations:**

```swift
// Which should I call?
manager.saveConfiguration(input: "caps", output: "esc")  // KanataManager
configService.writeConfig(content: "...")               // ConfigurationService
KanataConfigGenerator.generate(from: mappings)          // Static method
manager.configBackupService.create()                    // ConfigBackupManager

// They're all doing slightly different things!
```

**Recommendation:** Single `ConfigurationManager` API:
```swift
class ConfigurationManager {
    // Unified API
    func save(_ mappings: [KeyMapping]) async throws
    func load() async throws -> [KeyMapping]
    func createBackup() async throws -> Backup
    func restore(_ backup: Backup) async throws
    func validate() async throws -> ValidationResult
    func watchForChanges(_ handler: @escaping () -> Void)
    
    // Internal: delegates to specialized services
    private let fileService: ConfigurationService
    private let backupService: ConfigBackupManager
    private let generatorService: KanataConfigGenerator
}
```

---

### 9. SystemValidator vs MainAppStateController Overlap

**Two similar validation components:**

1. **SystemValidator** (223 lines)
   - Stateless validation
   - Used by: MainAppStateController, Wizard
   - Defensive assertions enabled
   - Runs full system checks

2. **MainAppStateController** (286 lines)
   - ObservableObject wrapper around SystemValidator
   - Used by: UI Views
   - Manages @Published state
   - Coordinates app startup

**Potential Issue:** Two layers of abstraction for same validation

**Should be:** One validator class + direct use from UI (via @State)
- Remove MainAppStateController wrapper
- Use SystemValidator directly with @State
- Reduces indirection by 50%

**Current flow:**
```
UI → MainAppStateController → SystemValidator → Oracle
```

**Better flow:**
```
UI → @State(SystemValidator.Snapshot) → SystemValidator → Oracle
```

---

### 10. Unused Test Infrastructure

**Contracts directory** mostly unused in actual code:
```swift
// 8 protocol files, 1,000+ lines
// Actually used in code: ~5%

// Only these are semi-used:
LifecycleControlling (in KanataManager)
// All others are interface debt
```

---

## Code Organization Issues

### Directory Structure Confusion

```
Sources/KeyPath/
├── Core/Contracts/           ⚠️ 8 protocol files (1,000 lines, minimal use)
├── Infrastructure/
│   ├── Config/
│   ├── Privileged/
│   └── Testing/
├── InstallationWizard/       ⚠️ 44 files, 17,441 lines (45% of codebase)
├── Managers/                 ⚠️ Large files here (KanataManager, KanataConfigManager)
├── Models/                   ✅ Clear
├── Services/                 ✅ Generally clear
├── UI/                       ⚠️ Some large views
├── Utilities/                ⚠️ Miscellaneous collection
└── Resources/
```

**Issues:**
1. **Contracts** directory suggests a DDD-style architecture that isn't actually practiced
2. **Managers** vs **Services** distinction unclear
3. **Utilities** is a dumping ground (Logger, FeatureFlags, AppRestarter, SoundManager, etc.)
4. **InstallationWizard** is so large it should be its own module

---

## Code Quality Metrics

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| **Largest file** | 2,820 lines | <1,000 | 🔴 2.8x over |
| **Unused protocols** | 1,000+ lines | 0 | 🔴 Significant debt |
| **Duplicate loggers** | 2 | 1 | 🟡 Minor issue |
| **God objects** | 1 (KanataManager) | 0 | 🔴 Critical |
| **UI views >1,000 lines** | 3 | 0 | 🟡 Could be split |
| **Wizard single file** | 1 (LaunchDaemonInstaller: 2,465) | 3-4 files | 🔴 Over-unified |
| **Clear entry points** | Partial | Complete | 🟡 Good but some confusion |
| **Test coverage** | Good | Good | ✅ Excellent |

---

## Specific File-Level Recommendations

### Critical (Do First)

1. **KanataManager.swift** (2,820 lines)
   - **Action:** Extract 4 focused coordinators
   - **Target:** Reduce to 800 lines
   - **Effort:** 3-4 days
   - **Files to create:**
     - `ProcessLifecycleCoordinator.swift` (~500 lines)
     - `ServiceHealthCoordinator.swift` (~300 lines)
     - `DiagnosticsCoordinator.swift` (~400 lines)
     - `PermissionCoordinator.swift` (~200 lines)

2. **Core/Contracts/** directory (1,000+ lines)
   - **Action:** Delete 5 unused protocols
   - **Delete:** PermissionChecking.swift, EventTapping.swift, EventProcessing.swift, OutputSynthesizing.swift, ConfigurationProviding.swift
   - **Keep:** Logging.swift, LifecycleControlling.swift, PrivilegedOperations.swift
   - **Target:** Reduce from 1,000 to 150 lines
   - **Effort:** 2 hours

3. **WizardLogger.swift** (46 lines)
   - **Action:** Delete and consolidate with AppLogger
   - **Replace:** All WizardLogger calls with AppLogger
   - **Fix:** Remove hardcoded developer path
   - **Effort:** 1 hour

### High Priority (Do Second)

4. **LaunchDaemonInstaller.swift** (2,465 lines)
   - **Action:** Split into 4 files
   - **Target:** 600 lines each
   - **Files:**
     - `LaunchDaemonManager.swift` - Service lifecycle
     - `LaunchDaemonHealthChecker.swift` - Health monitoring
     - `LaunchDaemonRepair.swift` - Recovery/diagnostics
     - `PlistGenerator.swift` - Config generation
   - **Effort:** 2-3 days

5. **PermissionService.swift** (79 lines of stubs)
   - **Action:** Delete file, replace calls with PermissionOracle
   - **Search & replace:** ~5 call sites
   - **Effort:** 1-2 hours

6. **WizardDesignSystem.swift** (955 lines)
   - **Action:** Split into 5 files
   - **Target:** 100-200 lines each
   - **Effort:** 1 day

### Medium Priority (Do Third)

7. **Large UI Views** (SettingsView, ContentView, DiagnosticsView)
   - **Action:** Extract sub-views to separate files
   - **Target:** 300-500 lines per file
   - **Effort:** 2-3 days total

8. **Configuration System Consolidation**
   - **Action:** Create unified ConfigurationManager API
   - **Target:** Single entry point, delegates internally
   - **Effort:** 1-2 days

9. **Navigation State Consolidation** (WizardStateMachine/StateManager/Interpreter/Engine)
   - **Action:** Reduce 5 files to 2
   - **Target:** 200 lines each
   - **Effort:** 1 day

---

## Positive Findings (Keep As-Is)

✅ **What's Working Well:**
1. **PermissionOracle** - Excellent single source of truth (671 lines, focused)
2. **SystemValidator** - Clean stateless validation
3. **ConfigurationService** - Good file operations API (842 lines, single responsibility)
4. **ServiceHealthMonitor** - Focused service monitoring
5. **DiagnosticsService** - Well-isolated diagnostics
6. **Error Handling** - KeyPathError is excellent
7. **Testing** - Comprehensive coverage with both XCTest and Swift Testing
8. **MVVM Separation** - KanataViewModel properly separated
9. **Build System** - Clear scripts and documentation

---

## Summary Table: Issues by Type

| Type | Count | Lines | Severity |
|------|-------|-------|----------|
| God objects | 1 | 2,820 | 🔴 Critical |
| Unused protocols | 5 | 1,000+ | 🔴 Critical |
| Large single-purpose files | 2 | 4,285 | 🔴 High |
| Duplicate logging | 2 | 100+ | 🟡 Medium |
| Large UI views | 3 | 3,451 | 🟡 Medium |
| Fragmented config logic | 5 files | 2,400 | 🟡 Medium |
| Navigation state duplication | 5 files | 1,000 | 🟡 Medium |
| Legacy stubs | 2 files | 100+ | 🟢 Low |
| **TOTAL ADDRESSABLE** | **25** | **~16,000** | - |

---

## Estimated Effort to Fix

| Item | Effort | Impact |
|------|--------|--------|
| Break up KanataManager | 3-4 days | 🔴 Blocks contributions |
| Remove unused protocols | 2 hours | 🟡 Reduces confusion |
| Consolidate logging | 1-2 hours | 🟢 Minor cleanup |
| Split LaunchDaemonInstaller | 2-3 days | 🟡 Improves readability |
| Delete PermissionService stubs | 1-2 hours | 🟢 Reduces debt |
| Split WizardDesignSystem | 1 day | 🟡 Improves navigation |
| Refactor large UI views | 2-3 days | 🟡 Better testability |
| Consolidate config API | 1-2 days | 🟡 Clearer API |
| Navigation state cleanup | 1 day | 🟡 Simpler logic |
| **TOTAL** | **~14-16 days** | - |

---

## Recommendations Priority Order

### 🔥 Do First (Critical)
1. **Break up KanataManager** - This is the #1 blocker
2. **Delete unused protocols** - Clear technical debt
3. **Delete deprecated stubs** - Remove confusion

### 🟡 Do Second (Important)
4. **Split LaunchDaemonInstaller** - Very large file
5. **Consolidate logging** - Reduce duplication
6. **Split WizardDesignSystem** - Easier to find things

### 🟢 Do Third (Nice to Have)
7. **Consolidate configuration API** - Clearer for contributors
8. **Simplify navigation state** - Reduce indirection
9. **Refactor large UI views** - Better testability

---

## Bottom Line

**The codebase is 70% good, 30% problematic.**

The problems are concentrated in:
1. **One mega-file** (KanataManager) that must be split
2. **Unused abstractions** that create confusion
3. **Fragmented responsibilities** across multiple similar files

All issues are **fixable without major architectural changes**. The bones are good, just needs cleanup.

**Estimated path to production-ready:** 2-3 weeks of focused refactoring

