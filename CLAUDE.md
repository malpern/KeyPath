# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CURRENT SESSION STATUS

**LATEST WORK:** UX improvements and config validation hardening (October 30, 2025)

**Recent Commits:**
- feat: comprehensive UX improvements and config validation hardening (commit 6bc628a)
  - Real-time key display during recording
  - Instant recording mode switching
  - Config validation on write AND read
  - Auto-recovery from paused state during save
  - Toast notification improvements
  - Code signature preservation with ditto

**Previous Session Work:**
- feat: detect and fix Karabiner driver version mismatch (commit 7834e90) - **INCOMPLETE**
- fix: detect VirtualHID driver activation errors in wizard (commit 8a47f72)
- fix: improve wizard status detection accuracy (commit b80f02e)
- ci: reduce test timeout and enforce strict quality gates (commit 69838b3)
- perf: optimize test execution time by removing unnecessary sleeps (commit d6a9b2f)
- refactor: revert module split to single executable (ADR-010, commit b8aa567)

**⚠️ INCOMPLETE WORK (requires follow-up):**
- ADR-012: Karabiner driver version detection implemented but NOT wired to Fix button
- TODO: Connect VHIDDeviceManager.downloadAndInstallCorrectVersion() to WizardAutoFixer
- TODO: Show version mismatch dialog when user clicks Fix button
- TODO: When kanata v1.10 is released, update requiredDriverVersionMajor to 6
- HELPER.md: Phase 1 complete (coordinator extraction), Phase 2-4 pending (XPC helper)

**Core Architecture (Stable):**
- **Single Executable Target:** Reverted from split modules for simplicity (see ADR-010)
- **Fast Test Suite:** Tests complete in <5 seconds (removed 4.4s of sleeps, 625x faster)
- **TCP Communication:** Primary protocol between KeyPath and Kanata (no authentication - see ADR-013)
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

3. FUNCTIONAL VERIFICATION → Disabled in TCP-only mode
   └─ TCP connectivity check would require protocol implementation (currently not used)
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
- Shared resources (Oracle, TCP) must manage their own lifecycle

## 🚫 Critical Anti-Patterns to Avoid

### Permission Detection
❌ **Never bypass Oracle** - All permission checks must go through `PermissionOracle.shared`
❌ **Never check permissions from root process** - IOHIDCheckAccess unreliable for daemons
❌ **Never create multiple sources of truth** - Oracle only, no direct API calls
✅ **Always** use Oracle for GUI checks, verify functionality via TCP health checks

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

### ADR-012: Karabiner Driver Version ⚠️ INCOMPLETE
**Problem:** Kanata v1.9.0 requires driver v5.0.0, users may have v6.0.0
**Implemented:** Version detection, download logic
**TODO:** Wire to WizardAutoFixer Fix button, show user dialog
**Future:** Update to v6 when kanata v1.10 releases
**Files:** VHIDDeviceManager.swift, SystemValidator.swift, WizardAutoFixer.swift

### ADR-013: TCP Communication Without Authentication ⚠️ SECURITY
**Problem:** Kanata v1.9.0 TCP server does not support authentication (unlike UDP which had robust auth)
**Decision:** Use unauthenticated TCP for localhost IPC
**Rationale:**
- Kanata's tcp_server.rs explicitly ignores Authenticate messages
- TCP server binds to localhost only (127.0.0.1:37001) - not exposed to network
- Limited attack surface: can only trigger config reloads, not arbitrary code execution
- Config validation happens before reload (malformed configs rejected)
- Kanata already requires root privileges (TCC Input Monitoring)

**Security Implications:**
- ✅ Acceptable: Localhost-only IPC with minimal attack surface
- ⚠️ Risk: Any local process can send reload commands to Kanata
- ⚠️ Risk: No client identity verification

**Migration History:**
- Aug 2025: Used UDP with token-based authentication (commit b45dbdc)
- Oct 2025: Switched to TCP, discovered authentication not supported (commit ccbccc1)
- Oct 2025: Removed non-functional authentication checks (current state)

**Future Work:**
- Consider contributing TCP authentication to upstream Kanata
- Design: Session-based tokens similar to UDP implementation
- Design: Token exchange via initial handshake
- Design: Session expiry and token rotation
- Alternative: Switch back to UDP if authentication becomes critical

**Files:** KanataTCPClient.swift, WizardCommunicationPage.swift, WizardSystemStatusOverview.swift

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
netstat -an | grep 37001                                # TCP server
```

**Config:** `~/Library/Application Support/KeyPath/keypath.kbd`
**Hot reload:** TCP-based, no service restart needed

## TCP Server

- **Port:** Command-line arg `--port 37001` (NOT in .kbd file)
- **Auth:** No authentication (Kanata v1.9.0 TCP server doesn't support it - see ADR-013)
- **Security:** Localhost-only, connection pooling with proper timeouts

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