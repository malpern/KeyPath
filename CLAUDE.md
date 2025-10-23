# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CURRENT SESSION STATUS

**LATEST WORK:** Module split revert and test performance optimization (October 2025)

**Recent Commits:**
- ci: reduce test timeout and enforce strict quality gates (commit 69838b3)
- perf: optimize test execution time by removing unnecessary sleeps (commit d6a9b2f)
- refactor: revert module split to single executable (ADR-010, commit b8aa567)

**Core Architecture (Stable):**
- **Single Executable Target:** Reverted from split modules for simplicity (see ADR-010)
- **Fast Test Suite:** Tests complete in <5 seconds (removed 4.4s of sleeps, 625x faster)
- **UDP Communication:** Primary protocol between KeyPath and Kanata with secure token auth
- **PermissionOracle:** Single source of truth for all permission detection (DO NOT BREAK)
- **TCC-Safe Deployment:** Stable Developer ID signing preserves Input Monitoring permissions
- **Bundled Kanata:** Uses bundled binary for TCC stability and consistent experience

## Project Overview

KeyPath is a macOS application that provides keyboard remapping using Kanata as the backend engine. It features a SwiftUI frontend and a LaunchDaemon architecture for reliable system-level key remapping.

## High-Level Architecture

### System Design
```
KeyPath.app (SwiftUI) → KanataManager → launchctl → Kanata daemon
                     ↓                              ↓
              CGEvent Capture              VirtualHID Driver
                     ↓                              ↓
              User Input Recording          System-wide Remapping
```

### Core Components
- **KeyPath.app**: SwiftUI application with Liquid Glass UI (macOS 15+) for recording keypaths and managing configuration
- **LaunchDaemon**: System service (`com.keypath.kanata`) that runs Kanata
- **Configuration**: User config at `~/Library/Application Support/KeyPath/keypath.kbd`
- **System Integration**: Uses CGEvent taps for key capture and launchctl for service management
- **Notifications**: UserNotificationService with actionable buttons, frontmost gating, and TTL-based deduplication

### Key Manager Classes
- `KanataManager`: **Coordinator** - orchestrates services, handles daemon lifecycle and user interactions (NOT ObservableObject)
- `KanataViewModel`: **UI Layer (MVVM)** - ObservableObject with @Published properties for SwiftUI reactivity
- `ConfigurationService`: Configuration file management (reading, writing, parsing, validation, backup)
- `ServiceHealthMonitor`: Health checking, restart cooldown, recovery strategies
- `DiagnosticsService`: System diagnostics, log analysis, failure diagnosis
- `KeyboardCapture`: Handles CGEvent-based keyboard input recording (isolated service)
- `PermissionOracle`: **🔮 CRITICAL ARCHITECTURE** - Single source of truth for all permission detection
- `UserNotificationService`: macOS Notification Center integration with categories, actions, and intelligent gating
- `InstallationWizard/`: Multi-step setup flow with auto-fix capabilities
  - `SystemStatusChecker`: System state detection (MUST trust Oracle without overrides)
  - `WizardNavigationEngine`: State-driven wizard navigation logic
  - `WizardAutoFixer`: Automated issue resolution
- `ProcessLifecycleManager`: Manages Kanata process state and recovery
- `PermissionService`: Legacy TCC database utilities (Oracle handles logic)

### UI Architecture
- **AppGlass**: Abstraction for Liquid Glass visual effects (macOS 15+)
  - `headerStrong`: Bold glass effect for major headers
  - `cardBold`: Glass effect for card containers
  - Falls back to NSVisualEffectView materials on older macOS versions
  - Honors system "Reduce Transparency" accessibility setting
- **Design System**: Centralized color tokens and spacing in `WizardDesignSystem`
- **Window Management**: Custom titlebar accessories and draggable area views (experimental)

### 🔮 PermissionOracle Architecture (CRITICAL - DO NOT BREAK)

**THE FUNDAMENTAL RULE: Apple APIs ALWAYS take precedence over TCC database**

The PermissionOracle follows a strict hierarchy that was broken in commit 7f68821 and restored:

```
1. APPLE APIs (IOHIDCheckAccess from GUI context) → AUTHORITATIVE
   ├─ .granted/.denied → TRUST THIS RESULT (never bypass with TCC)
   └─ .unknown → Proceed to TCC fallback

2. TCC DATABASE → NECESSARY FALLBACK for .unknown cases
   ├─ REQUIRED to break chicken-and-egg problems in wizard scenarios
   ├─ When service isn't running, can't do functional verification  
   ├─ When wizard needs permissions before starting service
   └─ Can be stale/inconsistent (why it's not primary source)

3. FUNCTIONAL VERIFICATION → For accessibility status only
   └─ UDP connectivity test (cannot determine Input Monitoring)
```

**❌ NEVER DO THIS (what commit 7f68821 broke):**
- Bypass Apple API results with TCC database queries
- Use TCC database when Apple API returns definitive answers
- Assume TCC database is more current than Apple APIs

**✅ CORRECT BEHAVIOR (restored here):**
- Trust Apple API `.granted/.denied` results unconditionally  
- DO use TCC database when Apple API returns `.unknown` (necessary for wizard scenarios)
- TCC fallback is REQUIRED to break chicken-and-egg problems
- Log source clearly: "gui-check" vs "tcc-fallback"

**Historical Context:**
- **commit 71d7d06**: Original correct Oracle design
- **commit 7f68821**: ❌ Broke Oracle by always using TCC fallback  
- **commit 8445b36**: ✅ Restored Oracle Apple-first hierarchy
- **commit bbdd053**: ✅ Fixed UI consistency by removing SystemStatusChecker overrides

### 🚨 UI Consistency (CRITICAL LESSON - September 1, 2025)

**Problem:** Different UI components showed conflicting permission status.
- Main screen: ✅ Green checkmark
- Wizard screens: ❌ Red X marks

**Root Cause:** SystemStatusChecker contained Oracle overrides that were never removed after fixing the Oracle.

**Architecture Rule:** ALL UI components must use Oracle as single source of truth.

```swift
// ✅ CORRECT - All components use same Oracle API
let snapshot = await PermissionOracle.shared.currentSnapshot()
if snapshot.keyPath.inputMonitoring.isReady { /* show green */ }

// ❌ WRONG - Different components use different permission checks
// MainScreen: Oracle → Green ✅
// Wizard: SystemStatusChecker overrides Oracle → Red ❌
```

**Components That Must Use Oracle Consistently:**
- `StartupValidator` (main screen status) → Uses Oracle ✅
- `SystemStatusChecker` (wizard status) → MUST trust Oracle without overrides ✅
- `ContentView` status indicators → Uses Oracle ✅
- All permission UI components → Must use Oracle ✅

**Never Add These SystemStatusChecker Overrides Again:**
- "TCC Domain Mismatch" logic that assumes system/user database differences
- "HARD EVIDENCE OVERRIDE" that parses kanata logs for permission errors
- Any logic that modifies Oracle results based on assumptions

**The Fix:** SystemStatusChecker now trusts Oracle unconditionally (commit bbdd053).

### 🎯 SystemStatusChecker Simplification (September 1, 2025)

**Problem:** Cache staleness was causing UI inconsistency even after waiting for service ready.
- StartupValidator properly waits for kanata service to be ready
- But SystemStatusChecker returns cached results from BEFORE service was ready
- Wizard invalidates cache and sees fresh (correct) results
- Main screen shows stale errors, wizard shows green

**Root Cause:** SystemStatusChecker had a 2-second cache that was designed to prevent validation spam.
- Cache was originally added to handle rapid repeated validation calls
- But we already solved that by removing the Oracle update listener
- Validation now only runs on: app launch, wizard close, config updates, manual refresh
- These are infrequent enough that caching causes more problems than it solves

**The Solution:** Removed cache entirely from SystemStatusChecker.
- No more cache properties, timestamps, or TTL logic
- Every `detectCurrentState()` call runs fresh detection
- Eliminates entire class of timing bugs and staleness issues
- Keeps solution simple and maintainable
- Minimal performance impact since validation is infrequent

**Architectural Principle:** When you fix the root cause (validation spam), remove the workaround (cache).

### 🎯 Validation Spam Fix (September 1, 2025 - Final)

**Problem:** Even after removing cache, validation spam continued due to automatic listeners.
- StartupValidator listened to `kanataManager.$isRunning` publisher
- StartupValidator listened to `kanataManager.$lastConfigUpdate` publisher
- These fired during app launch, triggering multiple validations that cancelled each other
- First validation would start → second validation cancels it → third validation completes
- User saw brief error/spinner state from cancelled validations

**Root Cause:** Automatic revalidation on system state changes.
- Originally added to keep UI fresh when system changes
- But caused same validation spam problem as Oracle listener
- Multiple validations firing within milliseconds cancelled each other
- Each new validation reset `validationState = .checking` before running
- Cancelled validations left UI in `.checking` state

**The Solution:** Removed ALL automatic revalidation listeners.
- Removed `kanataManager.$isRunning` listener
- Removed `kanataManager.$lastConfigUpdate` listener
- Removed `PermissionOracle` update listener (already done earlier)
- Validation now ONLY runs when explicitly triggered:
  1. App launch (after service ready)
  2. Wizard close (with force: true to bypass throttle)
  3. Manual refresh

**Result:** Single validation runs on app launch, completes cleanly, shows correct status immediately.

**Final Issue:** Oracle cache invalidation in SystemStatusChecker caused interference.
- SystemStatusChecker.detectCurrentState() always invalidated Oracle cache (line 116)
- When wizard auto-opened at app launch, it invalidated cache during StartupValidator's check
- This caused CancellationError in shared UDP client
- StartupValidator saw "UDP Server Not Responding" and showed error

**Final Fix:** Removed Oracle cache invalidation from SystemStatusChecker.
- Oracle already has its own 5-second cache management
- Concurrent validations (StartupValidator + SystemStatusChecker) no longer interfere
- Each validation gets consistent Oracle data without cancellation

**Key Architectural Lesson:** Shared resources (Oracle, UDP client) must not be invalidated by one caller while another is using them. Let each resource manage its own lifecycle.

**Persistent Issue:** ContentView still had onChange listeners triggering validation.
- Even after removing Combine listeners in StartupValidator
- ContentView had SwiftUI `.onChange(of: kanataManager.lastConfigUpdate)` and `.onChange(of: kanataManager.currentState)`
- These fired during app launch when KanataManager updated state
- Triggered refreshValidation() which cancelled StartupValidator's initial validation
- Multiple validations ran and cancelled each other

**Final Fix:** Removed onChange validation triggers from ContentView.
- Kept status message for config updates
- Removed `startupValidator.refreshValidation()` calls
- Validation now ONLY triggered by: app launch, wizard close, manual refresh button
- No more automatic revalidation on state changes anywhere in the codebase

**Still Persistent (Restart Issue):** Multiple notification handlers causing duplicate validations.
- ContentView had 4 different handlers that could trigger validation:
  1. Wizard sheet `onDismiss` → removed
  2. NotificationCenter `.wizardClosed` → removed
  3. NotificationCenter `.kp_startupValidate` → removed (consolidated)
  4. NotificationCenter `.kp_startupRevalidate` → kept as single source
- StartupCoordinator posted BOTH `.kp_startupValidate` AND `.kp_startupRevalidate` → fixed to post only `.kp_startupRevalidate`
- When wizard closed, 3 handlers fired simultaneously causing 3 concurrent validations
- Logs showed 3 validations starting within 2 seconds, all cancelling each other

**Ultimate Fix:** Consolidated to single validation trigger.
- All validation now triggered via `.kp_startupRevalidate` notification only
- StartupCoordinator: posts `.kp_startupRevalidate` at T+1.0s (removed duplicate at T+1.5s)
- Wizard close: posts `.kp_startupRevalidate` (removed sheet onDismiss and `.wizardClosed` handlers)
- Result: ONE validation runs per trigger event, no more cancellations

**Architectural Lesson:** When using notifications, have ONE publisher and ONE subscriber per event. Multiple handlers for the same logical event cause duplicate processing and race conditions.

### 🎯 Validation Architecture Refactor (September 2025 - Phase 1-3)

**Problem:** Despite multiple fixes, validation spam kept reappearing through new automatic trigger paths. The root cause was architectural - reactive patterns (Combine, onChange, NotificationCenter) created cascading updates that were hard to track and prevent.

**Solution:** Surgical replacement of validation subsystem with stateless, pull-based model and defensive assertions.

#### Phase 1: SystemValidator (Stateless Foundation)
**Created:**
- `SystemValidator.swift` - Stateless validator with NO caching, NO @Published properties
- `SystemSnapshot.swift` - Pure data model with computed properties for UI
- **4 Defensive Assertions:**
  1. 🚨 **Validation spam detection** - Crashes if concurrent validations detected
  2. ⚠️ **Rapid-fire detection** - Logs warning if validations < 0.5s apart
  3. 🔍 **Oracle freshness check** - Asserts Oracle cache is working (< 5s old)
  4. 📊 **Snapshot staleness check** - Asserts UI isn't showing old data (< 30s old)

**Key Design:**
```swift
@MainActor
class SystemValidator {
    private static var activeValidations = 0  // Defensive counter

    func checkSystem() async -> SystemSnapshot {
        // 🚨 CRASH if concurrent validation detected
        precondition(activeValidations == 0, "VALIDATION SPAM DETECTED!")
        activeValidations += 1
        defer { activeValidations -= 1 }

        // Pure validation - no side effects, no caching
        let permissions = await oracle.currentSnapshot()
        let components = checkComponents()
        let conflicts = await checkConflicts()

        return SystemSnapshot(permissions, components, conflicts, Date())
    }
}
```

#### Phase 2: Wizard Integration
**Modified:**
- `WizardStateManager` - Now uses SystemValidator instead of SystemStatusChecker
- `SystemSnapshotAdapter` - Converts new format to old wizard UI format (temporary adapter)

**Result:** Wizard now uses SystemValidator with defensive assertions active.

#### Phase 3: Main App Integration
**Replaced:**
- ~~`StartupValidator.swift`~~ → `MainAppStateController.swift`
- Removed ALL automatic validation triggers (Combine, onChange, NotificationCenter listeners)
- Explicit validation ONLY on:
  1. App launch (one-time, after service ready)
  2. Wizard close (explicit notification)
  3. Manual refresh button (user action)

**New Architecture:**
```swift
@MainActor
class MainAppStateController: ObservableObject {
    @Published var validationState: ValidationState
    private var validator: SystemValidator
    private var hasRunInitialValidation = false

    // ONLY public method - explicit validation
    func performInitialValidation() async {
        guard !hasRunInitialValidation else { return }
        hasRunInitialValidation = true

        await kanataManager.waitForServiceReady()
        let snapshot = await validator.checkSystem()  // Assertions active
        updateState(from: snapshot)
    }
}
```

**Results (Validated September 29, 2025):**
- ✅ **Before refactor:** Validations 0.007s apart (validation spam!)
- ✅ **After refactor:** Minimum 0.76s spacing (100x improvement)
- ✅ **Zero validation spam warnings** in production testing
- ✅ **Zero assertion crashes** (means no spam occurring)
- ✅ **Defensive assertions working** - Would crash immediately if spam detected

**Key Metrics:**
- Lines reduced: ~1,300 lines of complex orchestration → ~600 lines of simple validation
- Validation files: StartupValidator + SystemStatusChecker → SystemValidator + MainAppStateController
- Automatic triggers removed: 8+ reactive listeners → 0 (explicit only)

**Architectural Lessons:**
1. **Pull > Push:** Explicit validation requests are easier to reason about than reactive cascades
2. **Defensive assertions catch bugs early:** Crashing is better than silent validation spam
3. **Stateless services are predictable:** No caching = no staleness bugs
4. **Single source of truth:** One validator, one state, one update path

**Future Work (Optional):**
- Phase 5: Remove `SystemSnapshotAdapter`, update wizard UI to use `SystemSnapshot` directly
- Extract more responsibilities from `KanataManager` (4,400 lines → target ~1,200 lines)

## 🚫 Critical Anti-Patterns to Avoid

### 1. Permission Detection Anti-Patterns

```swift
// ❌ NEVER DO THIS - Creates inconsistent state
func checkPermissionsDirectly() -> Bool {
    let axGranted = AXIsProcessTrusted()
    let imGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    return axGranted && imGranted  // Bypasses Oracle!
}

// ❌ NEVER DO THIS - Multiple sources of truth
if PermissionService.hasAccessibility() && Oracle.snapshot().accessibility.isReady {
    // Which one is correct? Creates impossible debugging
}

// ❌ NEVER DO THIS - Side effects during checking
func checkInputMonitoring() -> Bool {
    // IOHIDCheckAccess can prompt user or auto-add to System Settings!
    return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
}
```

### 2. Validation Anti-Patterns

```swift
// ❌ NEVER DO THIS - Automatic validation triggers
.onChange(of: kanataManager.isRunning) { _ in
    Task { await validator.refreshValidation() }  // Creates validation spam!
}

// ❌ NEVER DO THIS - Multiple notification handlers for same event
NotificationCenter.default.addObserver(forName: .wizardClosed) { _ in validate() }
NotificationCenter.default.addObserver(forName: .kp_startupRevalidate) { _ in validate() }
// Both fire for wizard close → duplicate validations

// ❌ NEVER DO THIS - Manual status override
func forcePermissionStatus() {
    isPermissionGranted = true  // Oracle will contradict this
}
```

### 5. MVVM Anti-Patterns

```swift
// ❌ NEVER DO THIS - Business logic in ViewModel
class KanataViewModel: ObservableObject {
    func startKanata() async {
        // Direct process management - belongs in Manager!
        let process = Process()
        process.launchPath = "/usr/local/bin/kanata"
        process.launch()
    }
}

// ❌ NEVER DO THIS - Views accessing Manager directly (skip ViewModel)
struct ContentView: View {
    @EnvironmentObject var kanataManager: KanataManager  // Should be KanataViewModel!
}

// ❌ NEVER DO THIS - Manager with @Published properties
@MainActor
class KanataManager: ObservableObject {  // Should NOT be ObservableObject
    @Published var isRunning = false  // UI state belongs in ViewModel
}

// ✅ CORRECT - Proper MVVM separation
@MainActor
class KanataManager {  // Pure coordinator, not ObservableObject
    internal var isRunning = false  // Internal state for services

    func getCurrentUIState() -> KanataUIState {
        KanataUIState(isRunning: isRunning, ...)
    }
}

@MainActor
class KanataViewModel: ObservableObject {  // UI layer
    @Published var isRunning = false  // UI-reactive state
    private let manager: KanataManager

    var underlyingManager: KanataManager { manager }  // For business logic components

    func startKanata() async {
        await manager.startKanata()  // Delegate to manager
        await syncFromManager()      // Update UI state
    }
}

struct ContentView: View {
    @EnvironmentObject var kanataViewModel: KanataViewModel  // ViewModel for UI

    private var kanataManager: KanataManager {  // Manager for business logic
        kanataViewModel.underlyingManager
    }
}
```

### 3. Service Management Anti-Patterns

```swift
// ❌ NEVER DO THIS - Service management without health checks
func startKanataService() {
    launchctl("load", plistPath)
    // Service might fail to start, create zombies, or conflict
}

// ❌ NEVER DO THIS - Restart loops without cooldown
func ensureServiceRunning() {
    if !isRunning {
        restart()
        ensureServiceRunning()  // Infinite loop!
    }
}
```

### 4. Root Process Permission Anti-Patterns

```swift
// ❌ NEVER DO THIS - Trust kanata's self-reported permission status
let tcpStatus = await kanataClient.checkMacOSPermissions()
if tcpStatus.input_monitoring == "granted" {
    // This can be false negative on macOS!
}

// ❌ NEVER DO THIS - Check permissions from root process context
func checkInputMonitoringFromDaemon() -> Bool {
    return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    // Unreliable for root processes
}

// ✅ CORRECT - Check from GUI, verify functionality via daemon
let guiCheck = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
let functionalCheck = await kanataClient.testKeyCapture()
let shouldStart = guiCheck && functionalCheck.canAccess
```

### 6. Test Performance Anti-Patterns

```swift
// ❌ NEVER DO THIS - Real sleeps for time-based operations
func testCooldownBehavior() async {
    await monitor.recordStartAttempt(timestamp: Date())
    try? await Task.sleep(nanoseconds: 2_500_000_000)  // 2.5 seconds!
    await monitor.recordStartAttempt(timestamp: Date())
}

// ✅ CORRECT - Mock time control
func testCooldownBehavior() async {
    // Use backdated timestamp (instant!)
    await monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-3.0))
    await monitor.recordStartAttempt(timestamp: Date())
}

// ❌ NEVER DO THIS - Defensive sleeps for synchronous operations
func testRecordingState() async {
    coordinator.toggleInputRecording()
    try? await Task.sleep(nanoseconds: 150_000_000)  // Unnecessary
    XCTAssertTrue(coordinator.isInputRecording())
}

// ✅ CORRECT - No sleep for synchronous operations
func testRecordingState() async {
    coordinator.toggleInputRecording()
    // State updates are synchronous, no sleep needed
    XCTAssertTrue(coordinator.isInputRecording())
}

// ✅ ACCEPTABLE - Minimal sleep for genuine async behavior
func testAsyncCallback() async {
    captureStub.triggerCapture(with: sequence)
    try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms for async propagation
    XCTAssertFalse(coordinator.isInputRecording())
}
```

**Test Performance Guidelines:**
1. Ask: "Is this testing MY code or the language/framework?"
2. Default to NO sleeps - only add if absolutely necessary
3. Use mock time control patterns (backdated timestamps, injectable clocks)
4. Keep necessary async sleeps minimal (10-50ms, not 300ms+)
5. Tests should complete in milliseconds, not seconds

## 📜 Architecture Decision Records

### ADR-001: Oracle Pattern for Permission Detection
**Decision:** Single source of truth actor with deterministic hierarchy
**Status:** Accepted ✅
**Consequences:** Eliminated inconsistent permission detection, 100% reliability

### ADR-002: State-Driven Wizard Architecture
**Decision:** Pure functions for state detection, deterministic navigation
**Status:** Accepted ✅
**Consequences:** Handles 50+ edge cases automatically, predictable behavior

### ADR-003: Separate LaunchDaemon Services
**Decision:** Individual services for Kanata, VirtualHID Manager, VirtualHID Daemon
**Status:** Accepted ✅
**Consequences:** Granular lifecycle management, targeted failure recovery

### ADR-004: Manager Consolidation
**Decision:** Consolidate SimpleKanataManager functionality into KanataManager
**Status:** Completed ✅ (August 2025)
**Rationale:** SimpleKanataManager was a thin UI wrapper - functionality better integrated directly
**Consequences:** Single manager class, simpler architecture, but file now too large (4,400 lines)

### ADR-005: Root Process Permission Detection Limitations
**Decision:** Move permission checking from Kanata daemon to GUI context
**Status:** Completed ✅ (August 2025)
**Rationale:** IOHIDCheckAccess() unreliable for root processes on macOS - returns false negatives even when permission granted and functional
**Evidence:** Kanata captures keystrokes successfully while reporting "input_monitoring": "denied" via UDP API
**Consequences:** Reliable permission detection, matches industry best practices (Karabiner-Elements pattern)

### ADR-006: Oracle Apple API Priority Architecture
**Decision:** Apple APIs (IOHIDCheckAccess from GUI context) take absolute precedence over TCC database
**Status:** ✅ RESTORED (commits 8445b36, 87c36ca - September 1, 2025)
**Problem:** Commit 7f68821 broke Oracle by bypassing Apple APIs with TCC database even when APIs returned definitive results
**Solution:** Apple API results `.granted/.denied` are AUTHORITATIVE; TCC database used ONLY when Apple API returns `.unknown`

### ADR-007: UI Permission Detection Consistency
**Decision:** Remove all Oracle overrides from SystemStatusChecker to ensure UI consistency
**Status:** ✅ COMPLETED (commit bbdd053 - September 1, 2025)
**Problem:** Different UI components showed conflicting permission status
**Solution:** SystemStatusChecker now trusts Oracle results unconditionally; all UI uses single source

### ADR-008: Validation Architecture Refactor
**Decision:** Replace reactive validation (Combine/onChange/NotificationCenter) with stateless pull-based model
**Status:** ✅ COMPLETED (September 29, 2025 - Phases 1-4)
**Problem:** Validation spam from cascading reactive updates (validations 0.007s apart)
**Solution:** Stateless SystemValidator with defensive assertions, explicit-only validation triggers
**Results:** 100x improvement (0.007s → 0.76s spacing), zero validation spam, 54% code reduction
**Replaced:** StartupValidator → MainAppStateController

### ADR-009: KanataManager Service Extraction & MVVM
**Decision:** Break up 4,021-line god object into focused services and implement MVVM architecture
**Status:** ✅ COMPLETED (September 29-30, 2025 - Phases 1-6)
**Problem:** KanataManager violated Single Responsibility Principle with 10+ concerns in one class
**Solution:** Surgical extraction of services alongside existing code, MVVM separation for UI state
**Architecture:**
```
KanataManager (coordinator, 3,495 lines)
  ├─ ConfigurationService (818 lines) - Config file management
  ├─ ServiceHealthMonitor (347 lines) - Health checks & restart logic
  ├─ DiagnosticsService (537 lines) - System diagnostics & analysis
  └─ KanataViewModel (256 lines) - UI state (@Published properties)
```
**Results:**
- Services extracted with protocol-based interfaces (testable)
- MVVM separation: Manager = business logic, ViewModel = UI state
- Manager no longer ObservableObject (no @Published properties)
- Comprehensive test coverage for all services
- Zero regressions, all functionality preserved
**Key Pattern:** Coexistence strategy (build alongside, test incrementally, switch safely)

### ADR-010: Module Split Revert
**Decision:** Revert from split-module architecture (KeyPath library + KeyPathApp executable) to single executable target
**Status:** ✅ COMPLETED (October 22, 2025 - commit b8aa567)
**Problem:** Module split introduced for Swift 6 stability created more problems than benefits
**Cost vs Benefit:**
- **Cost:** 60+ minutes marking types public, ongoing cognitive overhead, architecture violation fixes
- **Benefit:** None realized - Swift 6 works fine in single module
**Solution:** Simplified Package.swift from two targets to single `.executableTarget`
**Results:**
- ✅ Compiling project (2.6s build time)
- ✅ Simpler mental model
- ✅ No module boundary friction
- ✅ Documented decision for future reference
**The Pragmatism Test** (apply before adding architectural complexity):
1. "Would this exist in a 500-line MVP?"
2. "Am I solving a problem I actually have?"
3. "Does this help me ship faster?"
**Documentation:** DECISION_MODULE_SPLIT_REVERT.md, REVERT_SUMMARY.md

### ADR-011: Test Performance Optimization
**Decision:** Remove unnecessary sleep operations and use mock time control patterns
**Status:** ✅ COMPLETED (October 22, 2025 - commit d6a9b2f)
**Problem:** Tests took 7-10+ seconds and occasionally hung due to 12 sleep operations
**Solution:**
- Removed critical 2.5s sleep in ServiceHealthMonitorTests (used backdated timestamps)
- Removed 8 defensive sleeps totaling 4.4 seconds (synchronous operations)
- Kept 4 necessary async sleeps (0.55s) for genuine async state propagation
**Results:**
- **625x speedup** on ServiceHealthMonitorTests (2.5s → 0.004s for 19 tests)
- **95% reduction** in total test time (7-10s → <5s)
- Tests no longer hang
- CI timeout reduced from 240s → 60s (75% reduction)
**Pattern: Mock Time > Real Sleeps**
```swift
// ✅ GOOD - Control time in tests
await monitor.recordStartAttempt(timestamp: Date().addingTimeInterval(-3.0))

// ❌ BAD - Wait for real time to pass
try? await Task.sleep(nanoseconds: 2_500_000_000)
```
**Documentation:** TEST_PERFORMANCE_ANALYSIS.md, TEST_PERFORMANCE_RESULTS.md

## ⚠️ Critical Reminders

**This architecture represents months of debugging complex macOS integration issues. Every design decision solves specific edge cases discovered through real-world usage.**

**Before making architectural changes:**
1. Review git history for the specific component
2. Check for related ADRs above
3. Verify Oracle consistency is maintained
4. Test validation behavior (no spam, proper spacing)
5. Confirm all UI shows consistent permission status

**The system works reliably because of this architecture, not despite it.**

### Notification System
The `UserNotificationService` provides intelligent user notifications with:
- **Categories**: Service failure, recovery, permission issues, informational
- **Actionable Buttons**: Open Wizard, Start Service, Open Input Monitoring/Accessibility settings, Open App
- **Smart Gating**: Only shows notifications when app is not frontmost (avoids duplicate alerts)
- **Deduplication**: Per-key TTL prevents notification spam (persisted in UserDefaults)
- **Delegate Actions**: Notification actions trigger appropriate app behaviors (retry start, open settings, etc.)
- **Integration Points**: MainAppStateController (permissions), ContentView (emergency stop), KanataManager (service failures)

### Installation Wizard Flow
The wizard follows a state-driven architecture with these key pages:
1. **Summary** - Overview of system state
2. **Conflicts** - Detect/resolve Karabiner conflicts
3. **Permissions** - Input monitoring & accessibility
4. **Components** - Kanata & Karabiner driver installation
5. **Service** - Start the Kanata daemon

## Build Commands

```bash
# Development build
swift build

# Release build
swift build -c release

# Production build with app bundle
./Scripts/build.sh

# Signed & notarized build  
./Scripts/build-and-sign.sh
```

## Test Commands

```bash
# Run a single test
swift test --filter TestClassName.testMethodName

# Run all tests (may prompt for passwords)
./run-tests.sh

# Unit tests only
swift test

# Force manual tests (requires password entry)
KEYPATH_MANUAL_TESTS=true ./run-tests.sh

# Individual integration tests
./test-kanata-system.sh   # Tests Kanata service operations
./test-hot-reload.sh      # Tests config hot-reload functionality
./test-service-status.sh  # Tests service status detection
./test-installer.sh       # Tests installation wizard
```

### Testing Notes

Integration tests may require administrator privileges for:
- Managing launchctl services
- Creating/modifying system files
- Running kanata with required permissions

For frequent testing, you may want to set up passwordless sudo locally (not recommended for production environments).

**Alternative with expect (if you have a password):**
```bash
# Using expect script for password automation
./Scripts/run-with-password.exp "your-password" sudo /usr/bin/pkill -f kanata
```

## Installation & Deployment

### Install to /Applications
```bash
# Build and copy to Applications
./Scripts/build.sh
cp -r build/KeyPath.app /Applications/

# Or for signed/notarized build
./Scripts/build-and-sign.sh
cp -r dist/KeyPath.app /Applications/
```

### System Service Installation
```bash
# Note: install-system.sh doesn't exist - service is managed by the app
# The app handles LaunchDaemon installation via InstallationWizard

# Uninstall everything
sudo ./Scripts/uninstall.sh
```

## Service Management

### launchctl Commands
```bash
# Start/restart service
sudo launchctl kickstart -k system/com.keypath.kanata

# Stop service  
sudo launchctl kill TERM system/com.keypath.kanata

# Check status
sudo launchctl print system/com.keypath.kanata

# View logs
tail -f /var/log/kanata.log

# Check if UDP server is running (if enabled)
netstat -an | grep 37000  # or your chosen port
```

### Configuration
- User config: `~/Library/Application Support/KeyPath/keypath.kbd`
- Hot reload: Configuration reloaded via UDP without service restart
- UDP server: Configured automatically by KeyPath with secure authentication

## Dependencies

- **Kanata**: Keyboard remapping engine (bundled with app)
- **Location**: `/Applications/KeyPath.app/Contents/Library/KeyPath/kanata` (bundled)
- **macOS 14.0+**
- **Permissions**: Accessibility (app) + Input Monitoring (kanata binary)
- **Communication**: UDP server with secure authentication

## Kanata Config Format

```lisp
(defcfg
  process-unmapped-keys yes
)

(defsrc caps)
(deflayer base esc)
```

### UDP Server Configuration

Kanata supports a UDP server for secure communication with KeyPath. The UDP server enables:
- Authentication-based session management
- Configuration validation and hot-reload
- Secure command execution with token-based auth

**Enable UDP Server:**
```bash
# Start kanata with UDP server (configured automatically by KeyPath)
/usr/local/bin/kanata --cfg /path/to/config.kbd --port 37000

# UDP server listens on localhost only by default for security
# Authentication required for all operations except initial handshake
```

**UDP Server Features:**
- **Secure Authentication**: Token-based authentication with session expiry
- **Session Management**: Sessions cached in Keychain with expiration tracking
- **Config Validation**: Live validation of keyboard configuration files
- **Hot Reload**: Configuration changes applied without service restart
- **Size Limits**: UDP packets limited to 1200 bytes for reliability

**Security Features:**
- All operations require valid authentication token
- Sessions expire automatically for security
- Localhost-only binding prevents external access
- Token storage via macOS Keychain for security

**IMPORTANT: UDP Configuration Method**
- UDP server is configured via **command line arguments only** (`--port <port>`)
- **NOT** configured in the `.kbd` config file
- The `.kbd` file only contains keyboard mappings, layers, and key definitions
- KeyPath manages UDP preferences and authentication automatically
- No manual token management required - handled by KeyPath

## Key Mapping

KanataManager handles special key conversions:
- `caps` → Caps Lock
- `space` → Space  
- `tab` → Tab
- `escape` → Escape
- `return` → Return
- `delete` → Backspace
- Multi-char outputs → Macro sequences

## Common Development Tasks

### Adding a New Feature
1. Create feature branch: `git checkout -b feature-name`
2. Implement changes following existing patterns
3. Run tests: `swift test`
4. Build and test app: `./Scripts/build.sh`
5. Create PR with description

### Debugging Issues
1. Check logs: `tail -f /var/log/kanata.log`
2. Verify permissions: System Settings > Privacy & Security
3. Check service status: `sudo launchctl print system/com.keypath.kanata`
4. Run diagnostics: Use DiagnosticsView in the app

### Working with the Wizard
- State detection is in `SystemStateDetector.swift`
- Auto-fix logic is in `WizardAutoFixer.swift`
- UI pages are in `InstallationWizard/UI/Pages/`
- All types are consolidated in `WizardTypes.swift`

## Troubleshooting

- **Service won't start**: Check kanata path with `which kanata`
- **Config invalid**: Test with `kanata --cfg "~/Library/Application Support/KeyPath/keypath.kbd" --check`
- **Permissions**: Grant in System Settings > Privacy & Security
- **Logs**: Check `/var/log/kanata.log`
- **Emergency stop**: Ctrl+Space+Esc disables all remapping

## Code Signing

Production builds require:
- Developer ID signing
- Runtime hardening
- Notarization via `build-and-sign.sh`

## Deployment Instructions

**CRITICAL: TCC-Safe Deployment Process**

For ALL deployments, use this TCC-safe process to preserve Input Monitoring permissions:

```bash
# Recommended deployment process:
./Scripts/build-and-sign.sh && cp -r dist/KeyPath.app /Applications/
```

**NEVER:**
- Use `build.sh` for production (lacks notarization)
- Move app to different locations during updates
- Use unsigned builds  
- Change bundle identifier or signing certificate

**Why This Matters:**
- Preserves stable TCC identity (Team ID + Bundle ID + Path)
- Users won't need to re-grant Input Monitoring permissions
- In-place replacement maintains TCC database entries

**Pre-Deployment Steps:**
1. Format code with Swift formatter (if SwiftFormat is available)
2. Fix linting issues with SwiftLint (if available): `swiftlint --fix --quiet`
3. **SKIP TESTS** unless explicitly requested (e.g., "run tests", "test before deploying")

This speeds up deployment by avoiding the test suite which can be time-consuming.

## Code Quality Commands

```bash
# Format Swift code (if SwiftFormat installed)
swiftformat Sources/ Tests/ --swiftversion 5.9

# Lint and auto-fix (if SwiftLint installed)
swiftlint --fix --quiet

# Check for issues without fixing
swiftlint
```

## Safety Features

1. **Emergency Stop**: Ctrl+Space+Esc immediately disables all remapping
2. **Config Validation**: All configs are validated before application
3. **Atomic Updates**: Configuration changes are atomic
4. **Timeout Protection**: 30-second startup timeout prevents hangs
5. **Process Recovery**: Automatic restart on crash via launchctl

## Testing Philosophy

- **Integration over unit tests** for system interactions
- **Test against real system** - minimize mocks
- **Fast feedback** through focused test scopes
- Tests are in `Tests/KeyPathTests/` and integration tests use real system calls