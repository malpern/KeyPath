# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CURRENT SESSION STATUS

**LATEST WORK:** InstallerEngine Façade Migration (Completed November 22, 2025)

**Recent Commits:**
- refactor: completed InstallerEngine migration (Phases 8-9)
  - Archived planning docs, verified manual steps
  - Removed legacy status plumbing from KanataManager
  - Updated ContentView and Settings to use InstallerEngine/SystemContext
- refactor: internal cleanup (Phase 7)
  - Extracted recipe logic to `InstallerEngine+Recipes.swift`
  - Unified health pipeline using `SystemValidator`
- feat: CLI migration (Phase 6)
  - All CLI commands (`install`, `repair`, `status`) now route through `InstallerEngine`

**Previous Session Work:**
- fix: robust app restart and XPC signature mismatch detection (Nov 17)
- feat: improve rules UI layout and document home row mods
- fix: SMAppService daemon registration and TCP validation

**⚠️ INCOMPLETE WORK (requires follow-up):**
- **Optimization:** Performance profiling for `InstallerEngine` if needed (currently fast enough)
- ADR-012: Karabiner driver version detection implemented but NOT wired to Fix button
- TODO: Connect VHIDDeviceManager.downloadAndInstallCorrectVersion() to WizardAutoFixer
- TODO: Show version mismatch dialog when user clicks Fix button
- TODO: When kanata v1.10 is released, update requiredDriverVersionMajor to 6
- HELPER.md: Phase 1 complete (coordinator extraction), Phase 2-4 pending (XPC helper)

**Core Architecture (Stable):**
- **InstallerEngine:** Primary façade for all installation/repair logic (Strangler Fig complete)
- **Single Executable Target:** Reverted from split modules for simplicity (see ADR-010)
- **Fast Test Suite:** Tests complete in <5 seconds
- **TCP Communication:** Primary protocol between KeyPath and Kanata (no authentication - see ADR-013)
- **PermissionOracle:** Single source of truth for all permission detection (DO NOT BREAK)
- **TCC-Safe Deployment:** Stable Developer ID signing preserves Input Monitoring permissions

## Project Overview

KeyPath is a macOS application that provides keyboard remapping using Kanata as the backend engine. It features a SwiftUI frontend and a LaunchDaemon architecture for reliable system-level key remapping.

## High-Level Architecture

### System Design
```
KeyPath.app (SwiftUI) → InstallerEngine → LaunchDaemon/PrivilegedHelper
          ↓                    ↓
    KanataManager      SystemContext (State)
          ↓
   TCP/Runtime Control
```

### Core Components
- **KeyPath.app**: SwiftUI application with Liquid Glass UI (macOS 15+)
- **InstallerEngine**: Unified façade for installation, repair, and system inspection
- **LaunchDaemon**: System service (`com.keypath.kanata`) that runs Kanata
- **Configuration**: User config at `~/Library/Application Support/KeyPath/keypath.kbd`
- **System Integration**: Uses CGEvent taps for key capture and launchctl for service management

### Key Manager Classes
- **`InstallerEngine`**: **The Façade** - Handles all "write" operations (install/repair/uninstall) and system inspection.
- **`KanataManager`**: **Runtime Coordinator** - orchestrates active service, handles config reloading, user interactions (NOT ObservableObject).
- `KanataViewModel`: **UI Layer (MVVM)** - ObservableObject with @Published properties for SwiftUI reactivity.
- `ConfigurationService`: Configuration file management (reading, writing, parsing, validation, backup).
- `ServiceHealthMonitor`: Health checking, restart cooldown, recovery strategies.
- `PermissionOracle`: **🔮 CRITICAL ARCHITECTURE** - Single source of truth for all permission detection.
- `UserNotificationService`: macOS Notification Center integration.
- `InstallationWizard/`:
  - `InstallerEngine` powers the wizard logic.
  - `WizardNavigationEngine`: State-driven wizard navigation.

### 🔮 PermissionOracle Architecture (CRITICAL - DO NOT BREAK)

**THE FUNDAMENTAL RULE: Apple APIs ALWAYS take precedence over TCC database**

1. **APPLE APIs** (IOHIDCheckAccess from GUI context) → **AUTHORITATIVE**
   - `.granted` / `.denied` → TRUST THIS RESULT
   - `.unknown` → Proceed to TCC fallback
2. **TCC DATABASE** → **NECESSARY FALLBACK** for `.unknown` cases
   - Required for chicken-and-egg wizard scenarios
3. **FUNCTIONAL VERIFICATION** → Disabled in TCP-only mode

**✅ CORRECT BEHAVIOR:**
- Trust Apple API results unconditionally.
- DO use TCC database only when Apple API returns `.unknown`.
- Log source clearly: "gui-check" vs "tcc-fallback".

### 🎯 Validation Architecture (InstallerEngine Era)

**Validation is now pull-based via `InstallerEngine.inspectSystem()`**:
- **`inspectSystem()`** returns a `SystemContext` snapshot.
- **`SystemValidator`** is the internal engine used by `inspectSystem()`.
- **No Reactive Spam**: We explicitly request context when needed (app launch, wizard open/close, refresh).

**Critical Design Pattern:**
```swift
let engine = InstallerEngine()
let context = await engine.inspectSystem() // Returns pure value struct
if context.permissions.inputMonitoring != .granted { ... }
```

## 🚫 Critical Anti-Patterns to Avoid

### Permission Detection
❌ **Never bypass Oracle** - All permission checks must go through `PermissionOracle.shared`.
❌ **Never check permissions from root process** - IOHIDCheckAccess unreliable for daemons.
✅ **Always** use Oracle for GUI checks.

### Service Management
❌ **Do not use KanataManager for installation** - Use `InstallerEngine.run(intent: .install)`.
❌ **Do not manually call launchctl** - Use `InstallerEngine` recipes.
❌ **No restart loops** - Use cooldown timers.

### Test Performance
❌ **No real sleeps** - Use backdated timestamps (`Date().addingTimeInterval(-3.0)`).
✅ **Mock time control** - Keep tests fast (<5s total).

### Test Seams (CRITICAL)
❌ **Never call real `pgrep`** - Tests using `InstallerEngine`, `RuntimeCoordinator`, or `SystemValidator` will deadlock.
✅ **Always use `KeyPathTestCase` base class** - Automatically sets up `VHIDDeviceManager.testPIDProvider = { [] }`.
✅ **Or manually set seam** - If not using base class: set `VHIDDeviceManager.testPIDProvider` in setUp/tearDown.

**Why?** `VHIDDeviceManager.detectConnectionHealth()` spawns `pgrep` subprocesses with 3s timeouts that deadlock during rapid parallel test execution.

## 📜 Architecture Decision Records

### ADR-015: InstallerEngine Façade (Completed Nov 2025) ✅
Unified all installation/repair logic into `InstallerEngine`.
- **Input**: `InstallIntent` (.install, .repair, .uninstall)
- **Output**: `InstallerReport`
- **Logic**: `inspectSystem()` → `makePlan()` → `execute()`
- **Replaces**: `WizardAutoFixer`, `LaunchDaemonInstaller` direct calls, `SystemStatusChecker`.

### ADR-001: Oracle Pattern ✅
Single source of truth for all permission detection.

### ADR-006: Oracle Apple API Priority ✅
Apple API results are AUTHORITATIVE.

### ADR-008: Validation Refactor ✅
Stateless `SystemValidator` behind `InstallerEngine`.

### ADR-009: Service Extraction & MVVM ✅
`KanataManager` broken down; `KanataViewModel` holds UI state.

### ADR-013: TCP Communication Without Authentication ⚠️
Used for localhost IPC. No auth supported by Kanata 1.9.0 TCP server.

### ADR-014: XPC Signature Mismatch Prevention ✅
Robust app restart logic to prevent mismatched helpers.

## Build Commands

```bash
swift build             # Development
./Scripts/build.sh      # Production (local)
./Scripts/build-and-sign.sh # Release (signed)
```

## Quick Deploy

**"dd"** → "Aye aye Captain!"
```bash
cd /Users/malpern/local-code/KeyPath && SKIP_NOTARIZE=1 ./build.sh
```
Deploys release build locally and restarts app.

## Test Commands

```bash
swift test
KEYPATH_MANUAL_TESTS=true ./run-tests.sh  # Force manual tests
KEYPATH_USE_SUDO=1 swift test             # Run tests with sudo (requires sudoers setup)
```

### Sudoers Configuration (Local Development Only)

For running tests that need admin privileges without osascript dialogs:

```bash
# Setup (one-time)
sudo ./Scripts/dev-setup-sudoers.sh

# Run tests with sudo instead of osascript
KEYPATH_USE_SUDO=1 swift test

# Remove before public release!
sudo ./Scripts/dev-remove-sudoers.sh
```

**How it works:**
- `KEYPATH_USE_SUDO=1` makes `LaunchDaemonInstaller` use `sudo -n` instead of osascript
- `TestEnvironment.useSudoForPrivilegedOps` controls the behavior
- Sudoers rules are scoped to KeyPath-specific paths only

**Files:**
- `Scripts/dev-setup-sudoers.sh` - Adds NOPASSWD rules to `/etc/sudoers.d/keypath-dev`
- `Scripts/dev-remove-sudoers.sh` - Removes the rules

## Code Quality

```bash
swiftformat Sources/ Tests/ --swiftversion 5.9
swiftlint --fix --quiet
```
