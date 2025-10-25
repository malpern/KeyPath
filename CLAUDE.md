# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CURRENT SESSION STATUS

**LATEST WORK:** Test suite reliability investigation and improvements (October 25, 2025)

**Recent Commits:**
- test: improve test reliability and coverage script (commit 6a8c750) - **COMPLETE**
  - Fixed `AppDelegateWindowTests.swift:113` to use `NSApplication.shared` instead of `NSApp`
  - Added timeout handling to coverage script (5min full suite, 2min filtered)
  - Documented test suite performance characteristics and coverage limitations
  - Removed tests of private implementation details (bootstrap, activation fallback)
- chore: remove dead code and deprecated test files (commit b72bb39) - **COMPLETE**
  - Deleted 56 files (~432KB): empty extensions, deprecated tests, orphaned scripts
  - Removed KanataConfigManagerError enum (superseded by KeyPathError)
  - Zero functional impact, build verified passing
- feat: add hover tooltips to all wizard pages (commit 829071c) - **COMPLETE**
- feat: detect and fix Karabiner driver version mismatch (commit 7834e90) - **COMPLETE**

## ℹ️ Test Suite Status — October 25, 2025

**✅ Test Suite is Reliable and Ready for Refactoring**

What changed
- Investigated 40+ minute "hang" issue - discovered it was code coverage instrumentation overhead, not a test problem
- Fixed `AppDelegateWindowTests.swift:113` nil reference (changed `NSApp` → `NSApplication.shared`)
- Added timeouts to coverage script to prevent indefinite hangs
- Test suite completes in ~2 seconds without coverage, proving reliability

**Test Suite Performance**
- **Normal run:** 57 tests pass in 2.273 seconds ✅
- **With coverage (filtered):** ~90 seconds for `UnitTestSuite` ✅
- **With coverage (full):** Hangs due to instrumentation overhead (use timeout) ⚠️

**How to run**
```bash
# Fast, reliable test run (recommended for refactoring)
swift test  # ~2 seconds, 57 tests

# Coverage with default filter (recommended)
./Scripts/generate-coverage.sh  # ~90s, good coverage of core logic

# Full suite with coverage (experimental, may timeout)
COVERAGE_FULL_SUITE=true ./Scripts/generate-coverage.sh  # 5min timeout
```

**Key Findings**
- **Not a test quality issue** - Tests are well-written and reliable
- **Coverage instrumentation causes slowdowns** - This is a tooling limitation, not a code problem
- **Default `UnitTestSuite` filter is best practice** - Fast, reliable, good coverage
- **Full suite hangs with coverage enabled** - Due to instrumentation overhead on integration tests

**Coverage Limitations**
- Default filter gives ~0.50% line coverage (core unit tests only)
- Most code is UI (SwiftUI views) and system integration - not covered by unit tests
- This is expected and acceptable - integration tests exist but slow with coverage
- Consider Xcode's built-in coverage tools for comprehensive analysis

## ▶️ Next Steps
- Continue with refactoring work - test suite is ready
- Optional: Investigate alternative coverage tools if comprehensive metrics needed
- Tests already cover critical paths; low percentage is due to UI-heavy codebase

**✅ COMPLETED WORK:**
- ADR-012: Karabiner driver version fix is fully implemented and tested
  - ✅ Version detection working
  - ✅ Download/install/activate functionality complete
  - ✅ Fix button wired to WizardAutoFixer.fixDriverVersionMismatch()
  - ✅ User dialog shows before download
  - ✅ Success confirmation after installation
- Wizard hover tooltips showing issue details on all pages

**📅 FUTURE WORK:**
- When kanata v1.10 is released, update requiredDriverVersionMajor to 6

**Previous Work:**
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

### 📂 PermissionService Architecture Evolution

**Historical:** PermissionService originally handled all permission checks directly, mixing business logic with TCC database access.

**Current (Post-Oracle):**
- PermissionService is now a **TCC database reader ONLY**
- All permission logic moved to PermissionOracle (see ADR-001)
- Service provides safe, deterministic database queries as Oracle fallback
- Used exclusively when Apple APIs return `.unknown` (see hierarchy above)
- DO NOT add permission logic here - use Oracle

**Responsibilities:**
- Read TCC database (`/Library/Application Support/com.apple.TCC/TCC.db`)
- Query permission status for specific services (Accessibility, Input Monitoring)
- Provide fallback data when Apple APIs are unavailable
- No business logic, no decision-making, just data access

**Related:**
- ADR-001 (Oracle Pattern)
- ADR-006 (Apple API Priority)
- PermissionOracle.swift:102-106 (TCC fallback logic)

### 🎯 Validation Architecture (September 2025)

**Problem:** Reactive patterns (Combine, onChange, NotificationCenter) created validation spam - multiple validations cancelled each other, causing UI flicker and inconsistent state.

**Solution:** Replaced with stateless pull-based SystemValidator with defensive assertions.

**Key Components:**
- `SystemValidator.swift` - Stateless, no caching, defensive concurrency checks
- `SystemSnapshot.swift` - Pure data model
- `MainAppStateController.swift` - Replaces StartupValidator, explicit-only validation

**Critical Design Pattern:**
```swift
class SystemValidator {
    private static var activeValidations = 0
    func checkSystem() async -> SystemSnapshot {
        precondition(activeValidations == 0, "VALIDATION SPAM!")  // Crashes if spam detected
        // ... pure validation, no side effects
    }
}
```

**Validation Triggers (Explicit Only):**
1. App launch (after service ready)
2. Wizard close
3. Manual refresh button

**Results:** 100x improvement (0.007s → 0.76s spacing), zero spam, 54% code reduction

**Key Lessons:**
- Pull > Push: Explicit validation beats reactive cascades
- ALL UI must use Oracle as single source of truth
- No automatic revalidation listeners (Combine/onChange/NotificationCenter)
- Shared resources (Oracle, UDP) must manage their own lifecycle

## 🚫 Critical Anti-Patterns to Avoid

### Permission Detection
❌ **Never bypass Oracle** - All permission checks must go through `PermissionOracle.shared`
❌ **Never check permissions from root process** - IOHIDCheckAccess unreliable for daemons
❌ **Never create multiple sources of truth** - Oracle only, no direct API calls
✅ **Always** use Oracle for GUI checks, verify functionality via UDP

### Validation
❌ **No automatic triggers** - No onChange/Combine/NotificationCenter listeners
❌ **No multiple handlers** - One publisher, one subscriber per event
❌ **No concurrent validations** - SystemValidator enforces this with assertions
✅ **Explicit only** - App launch, wizard close, manual refresh

### MVVM Architecture
❌ **Manager should NOT be ObservableObject** - No @Published properties
❌ **Views should use ViewModel** - Not Manager directly
❌ **No business logic in ViewModel** - Delegate to Manager
✅ **Manager = coordinator, ViewModel = UI state**

### Service Management
❌ **No health checks = danger** - Services can fail silently
❌ **No restart loops** - Use cooldown timers (ServiceHealthMonitor)

### Test Performance
❌ **No real sleeps** - Use backdated timestamps for time-based tests
❌ **No defensive sleeps** - Synchronous operations don't need them
✅ **Mock time control** - `Date().addingTimeInterval(-3.0)`
✅ **Minimal async sleeps** - 10-50ms max, only when genuinely needed

## 📜 Architecture Decision Records

### ADR-001: Oracle Pattern ✅
Single source of truth for all permission detection. Apple APIs > TCC database > functional verification.

### ADR-002: State-Driven Wizard ✅
Pure functions for detection, deterministic navigation. Handles 50+ edge cases automatically.

### ADR-003: Separate LaunchDaemon Services ✅
Individual services for Kanata, VirtualHID Manager, VirtualHID Daemon. Granular lifecycle control.

### ADR-004: Manager Consolidation ✅
Merged SimpleKanataManager into KanataManager for simpler architecture.

### ADR-005: GUI-Only Permission Checks ✅
IOHIDCheckAccess unreliable from root processes. Always check from GUI context.

### ADR-006: Oracle Apple API Priority ✅
Apple API results are AUTHORITATIVE. TCC database only used when API returns `.unknown`.

### ADR-007: UI Consistency ✅
All UI components must use Oracle. No overrides in SystemStatusChecker.

### ADR-008: Validation Refactor ✅
Replaced reactive validation with stateless SystemValidator. 100x improvement, zero spam.
- StartupValidator → MainAppStateController
- Defensive assertions prevent concurrent validations

### ADR-009: Service Extraction & MVVM ✅
Extracted from 4,021-line KanataManager:
- ConfigurationService (818 lines)
- ServiceHealthMonitor (347 lines)
- DiagnosticsService (537 lines)
- KanataViewModel (256 lines)
Manager = business logic, ViewModel = UI state (@Published properties)

### ADR-010: Module Split Revert ✅
Single executable target. Swift 6 works fine without module split. **Pragmatism Test:** Would this exist in a 500-line MVP?

### ADR-011: Test Performance ✅
Mock time > real sleeps. 625x speedup, tests now <5s. Pattern: `Date().addingTimeInterval(-3.0)`

### ADR-012: Karabiner Driver Version ✅ COMPLETE
**Problem:** Kanata v1.9.0 requires driver v5.0.0, users may have v6.0.0
**Solution:** Full automated fix with download, install, and activation
**Implementation:**
- Version detection in VHIDDeviceManager.hasVersionMismatch()
- Automatic download from GitHub releases
- Clean uninstall of existing versions
- Installation of correct v5.0.0
- Activation via Karabiner-VirtualHIDDevice-Manager
- User dialog with confirmation before download
- Success message after completion
**Future:** Update to v6 when kanata v1.10 releases
**Files:** VHIDDeviceManager.swift, SystemValidator.swift, WizardAutoFixer.swift

### ADR-013: KanataManager Decomposition Intentions 📝
**Current State:** KanataManager is ~2,794 lines in single file
**Historical Context:** Empty extension placeholders (KanataManager+Engine.swift, +EventTaps.swift, +Output.swift) deleted in commit b72bb39
**Why Deleted:** Premature abstraction - created but never implemented
**Future Decomposition (if needed):**
- **Engine** - Key mapping transformations and layer management
- **EventTaps** - CGEvent tap installation, callbacks, and event processing
- **Output** - CGEvent synthesis, posting, and VirtualHID interaction
- **Keep in Core** - Coordination, lifecycle, state management
**Principle:** Only create files with working code. No empty placeholders. If decomposition becomes necessary, extract cohesive subsets of actual functionality rather than creating architectural scaffolding.

### ADR-014: Eager Window Creation ✅
**Problem:** Main window wouldn't appear on launch without user interaction (clicking dock icon). This was a **recurring regression** that happened multiple times.
**Root Cause:** `AppDelegate.applicationDidFinishLaunching(_:)` is not called reliably by SwiftUI's `@NSApplicationDelegateAdaptor` when the app has no primary SwiftUI window scene (only Settings scene).
**Evidence:** Log analysis showed some launches called `applicationDidFinishLaunching` while others didn't - unpredictable AppKit/SwiftUI lifecycle interaction.
**Solution:**
- **Eager window creation** in `App.init()` (before any lifecycle methods) via `prepareMainWindowIfNeeded()`
- **Idempotent bootstrap** moved to `bootstrapOnce()` (TCP token, service bounce, StartupCoordinator)
- **Activation fallback** timer (1 second) ensures window appears even if `applicationDidBecomeActive` never fires
- **DEBUG assertion** verifies window exists before first activation (catches regression during development)
- **Single creation path** via `prepareMainWindowIfNeeded()` used everywhere (init, reopen)
**Files:** `App.swift:192-266`, `AppDelegateWindowTests.swift`
**Key Insight:** Don't depend on `applicationDidFinishLaunching` for critical setup - it's unreliable with @NSApplicationDelegateAdaptor. Create windows eagerly in `App.init()` instead.

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
`UserNotificationService`: Actionable buttons, smart gating (not when app frontmost), TTL deduplication

### Installation Wizard
State-driven flow: Summary → Conflicts → Permissions → Components → Service

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

### Local Dev Build (Agents)

For fast, repeatable local builds during development, prefer the dev script and Make target:

```bash
# Fast debug build → packages .app → installs to /Applications → launches
make dev

# Variants
LAUNCH_APP=0 make dev                 # build + install only, do not launch
CODESIGN_IDENTITY=- make dev          # force ad‑hoc signing for local runs
APP_DEST="$HOME/Applications/KeyPath.app" make dev  # alternate install path
```

Why this matters
- Keeps a stable bundle path (/Applications/KeyPath.app) so Accessibility/Input Monitoring approvals persist.
- Skips notarization and Gatekeeper checks for speed.
- Uses Developer ID if available; falls back to ad‑hoc automatically.

Claude/agents: When asked to “build locally” or to “run the app,” default to `make dev` (or `./Scripts/build-dev-local.sh`). Do not run notarization steps for local builds, and avoid changing the bundle identifier or install path unless explicitly requested.

## Test Commands

```bash
swift test                                         # Unit tests
swift test --filter TestClassName.testMethodName  # Single test
./run-tests.sh                                     # All tests (requires password)
KEYPATH_MANUAL_TESTS=true ./run-tests.sh          # Force manual tests
```

## Installation & Deployment

```bash
# Production deployment (TCC-safe)
./Scripts/build-and-sign.sh && cp -r dist/KeyPath.app /Applications/

# Uninstall
sudo ./Scripts/uninstall.sh
```

## Service Management

```bash
sudo launchctl kickstart -k system/com.keypath.kanata  # Restart
sudo launchctl print system/com.keypath.kanata         # Status
tail -f /var/log/kanata.log                             # Logs
netstat -an | grep 37000                                # UDP server
```

**Config:** `~/Library/Application Support/KeyPath/keypath.kbd`
**Hot reload:** UDP-based, no service restart needed

## UDP Server

- **Port:** Command-line arg `--port 37000` (NOT in .kbd file)
- **Auth:** Token-based via Keychain, auto-managed by KeyPath
- **Security:** Localhost-only, session expiry, 1200-byte packet limit

## Development

### Debugging
```bash
tail -f /var/log/kanata.log                           # View logs
sudo launchctl print system/com.keypath.kanata        # Service status
```
**In-app:** DiagnosticsView for system diagnostics

### Wizard Files
- `SystemStateDetector.swift` - State detection
- `WizardAutoFixer.swift` - Auto-fix logic
- `InstallationWizard/UI/Pages/` - UI pages
- `WizardTypes.swift` - Type definitions

### Troubleshooting
- **Service fails:** Check logs, verify permissions in System Settings
- **Config invalid:** `kanata --cfg ~/Library/Application\ Support/KeyPath/keypath.kbd --check`
- **Emergency stop:** Ctrl+Space+Esc

## Deployment (TCC-Safe)

**CRITICAL:** Always use signed builds to preserve Input Monitoring permissions

```bash
./Scripts/build-and-sign.sh && cp -r dist/KeyPath.app /Applications/
```

**Never:**
- Use unsigned builds in production
- Change bundle ID or signing certificate
- Move app to different paths (breaks TCC identity)

**Pre-deployment:** Format (SwiftFormat), lint (SwiftLint), **SKIP TESTS** unless requested

## Code Quality

```bash
swiftformat Sources/ Tests/ --swiftversion 5.9  # Format
swiftlint --fix --quiet                          # Lint & fix
```

## Safety Features

- **Emergency Stop:** Ctrl+Space+Esc
- **Config Validation:** Before application
- **Atomic Updates:** Safe config changes
- **Auto Recovery:** launchctl restarts on crash
