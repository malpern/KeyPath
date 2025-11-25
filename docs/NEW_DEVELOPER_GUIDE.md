# New Developer Guide

Welcome to KeyPath! This guide will help you understand the codebase architecture and get started contributing.

## What is KeyPath?

KeyPath is a macOS application that provides keyboard remapping using Kanata as the backend engine. It features:
- SwiftUI frontend for recording keypaths and managing configuration
- LaunchDaemon architecture for reliable system-level key remapping
- Installation Wizard for automated setup
- Deep macOS system integration (TCC permissions, VirtualHID drivers, service management)

## Quick Start: Your First 30 Minutes

### 1. Read These Files First (15 minutes)

```
1. README.md                          - What KeyPath does, how to build it
2. ARCHITECTURE.md                    - System design and permission hierarchy
3. CLAUDE.md                          - Critical architecture patterns and ADRs
4. Sources/KeyPath/App.swift          - Entry point and initialization flow
5. This guide (NEW_DEVELOPER_GUIDE.md)
```

### 2. Run the Project (5 minutes)

```bash
# Clone and build
cd /path/to/KeyPath
swift build

# Run tests (requires sudo password)
./run-tests.sh

# Build the app bundle for testing
./Scripts/build.sh

# Optional: exercise the new InstallerEngine façade (recommended)
KEYPATH_USE_INSTALLER_ENGINE=1 swift test --filter InstallerEngine
```

### 3.5 Quick code sample: façade-first service control

```swift
import KeyPathAppKit

let coordinator = ProcessCoordinator()

// Start/stop/restart always go through KanataService and only fall back to InstallerEngine if needed
let restarted = await coordinator.restartService()
if restarted {
    print("Kanata service is healthy")
} else {
    print("Restart failed even after InstallerEngine fallback")
}

// Need a full repair? Go through RuntimeCoordinator so it can log + inspect system context for you.
let runtimeCoordinator = RuntimeCoordinator()
let report = await runtimeCoordinator.runFullRepair(reason: "CLI repair")
if report.success {
    print("Repair finished (\(report.executedRecipes.count) steps)")
} else {
    print("Repair failed: \(report.failureReason ?? "unknown")")
}
```

`InstallerEngine` still powers installs/repairs under the hood, but new helpers should prefer `ProcessCoordinator` / `RuntimeCoordinator` so that cool-downs, health checks, and privilege handling stay centralized.

### 3. Explore Key Components (10 minutes)

Open these files in your editor to understand the core architecture:
- `Services/PermissionOracle.swift` - Single source of truth for permissions
- `Managers/KanataManager.swift` - Main process coordinator
- `UI/ContentView.swift` - Main recording UI
- `InstallationWizard/README.md` - Wizard overview (45% of codebase)

## Architecture Overview

### System Design

```
KeyPath.app (SwiftUI) → InstallerEngine → LaunchDaemon/PrivilegedHelper
          ↓                    ↓
    RuntimeCoordinator   SystemContext (State)
          ↓
   TCP/Runtime Control → Kanata daemon
          ↓                    ↓
   CGEvent Capture      VirtualHID Driver
          ↓                    ↓
   User Input Recording  System-wide Remapping
```

**Key Components:**
- **InstallerEngine**: Unified façade for installation, repair, and system inspection
- **RuntimeCoordinator**: Orchestrates active service, handles config reloading
- **KanataService**: Manages service lifecycle (start/stop/restart)
- **SystemContext**: Snapshot of system state (permissions, services, components)

### Directory Structure

```
Sources/KeyPath/
├── App.swift                 (378 lines)   - Entry point
├── Core/                     (2,160 lines) - Abstract contracts
├── Infrastructure/           (1,104 lines) - Config & utilities
├── InstallationWizard/       (17,985 lines) - 9-page setup flow
├── Managers/                 (4,872 lines)  - Process coordination
├── Models/                   (409 lines)    - Data structures
├── Services/                 (6,592 lines)  - System integration
├── UI/                       (5,902 lines)  - SwiftUI views
└── Utilities/                (526 lines)    - Helpers
```

**Total:** 120 Swift files, 39,928 lines of code

## Core Components You Must Understand

### 1. PermissionOracle 🔮 (CRITICAL)

**Location:** `Services/PermissionOracle.swift` (671 lines)

**What it does:** Single source of truth for ALL permission detection in KeyPath.

**Why it exists:**
- Prevents UI showing stale "denied" status while service works perfectly
- Handles macOS TCC quirks and race conditions
- Provides consistent 1.5s cached results (no permission check spam)

**How to use it:**
```swift
// Get current permission status
let snapshot = await PermissionOracle.shared.currentSnapshot()

// Check if system is ready
if snapshot.isSystemReady {
    print("✓ All permissions granted")
} else if let issue = snapshot.blockingIssue {
    print("✗ Blocked: \(issue)")
}

// After permission changes, force refresh
let updated = await PermissionOracle.shared.forceRefresh()
```

**CRITICAL RULE:** Never call `PermissionService`, `AXIsProcessTrusted()`, or `IOHIDCheckAccess()` directly. Always use the Oracle.

**See also:** Oracle Quick Start section in the file (lines 13-53)

### 2. KanataManager (Main Coordinator)

**Location:** `Managers/KanataManager.swift` + 5 extension files (2,820 lines total)

**What it does:** Orchestrates Kanata process lifecycle, configuration, and communication.

**Extension breakdown:**
- `KanataManager.swift` - Core state, initialization, health monitoring
- `+Lifecycle.swift` - Start/stop/restart operations
- `+Configuration.swift` - Config file I/O and validation
- `+Engine.swift` - UDP/TCP communication with Kanata
- `+EventTaps.swift` - CGEvent monitoring for key recording
- `+Output.swift` - Log parsing and monitoring

**How to use it:**
```swift
// KanataManager is NOT @ObservableObject
// UI uses KanataViewModel for @Published properties

// Start Kanata
try await manager.startKanata()

// Stop Kanata
try await manager.stopKanata()

// Update config
try await manager.updateConfiguration(newConfig)

// Get UI state snapshot
let uiState = manager.getCurrentUIState()
```

**See also:** Navigation comment in the file (lines 74-135)

### 3. InstallationWizard (45% of Codebase!)

**Location:** `InstallationWizard/` (44 files, 17,985 lines)

**What it does:** 9-page automated setup handling permissions, drivers, services.

**Why it's so large:** Legitimate complexity of macOS system integration:
- TCC permissions (Accessibility, Input Monitoring, Full Disk Access)
- Karabiner-Elements VirtualHID driver installation
- LaunchDaemon service management (requires root)
- Keyboard conflict detection and resolution
- UDP server configuration
- Driver version compatibility (v5 vs v6)

**Key files:**
- `Core/WizardNavigationEngine.swift` - State-driven page navigation
- `Core/WizardAutoFixer.swift` - Auto-remediation for 50+ edge cases
- `Core/LaunchDaemonInstaller.swift` - Service installation
- `UI/InstallationWizardView.swift` - Main wizard container
- `README.md` - Complete wizard documentation

**See also:** `InstallationWizard/README.md` for the full 9-page flow diagram

### 4. InstallerEngine (The Façade)

**Location:** `InstallationWizard/Core/InstallerEngine.swift`

**What it does:** Unified façade for all installation, repair, and system inspection operations.

**Key APIs:**
```swift
let engine = InstallerEngine()

// System inspection
let context = await engine.inspectSystem()

// Repair/install operations
let report = await engine.run(intent: .repair, using: broker)

// Health checks (façade methods)
let status = await engine.getServiceStatus()
let healthy = await engine.isServiceHealthy(serviceID: "com.keypath.kanata")
let health = await engine.checkKanataServiceHealth()
```

**Why use it:** All callers should go through InstallerEngine rather than directly using `LaunchDaemonInstaller`. This ensures consistent privilege handling, logging, and error reporting.

### 5. Services (Independent, Focused Components)

| Service | Purpose | Lines |
|---------|---------|-------|
| **PermissionOracle** | Permission detection | 671 |
| **KanataService** | Service lifecycle (start/stop/restart) | 400+ |
| **KeyboardCapture** | CGEvent input recording | 622 |
| **KarabinerConflictService** | Detect keyboard conflicts | 600 |
| **DiagnosticsService** | System analysis | 537 |
| **ConfigFileWatcher** | Monitor config changes | 496 |
| **SystemValidator** | Stateless validation | 269 |
| **ServiceHealthMonitor** | Recovery & restart | 348 |

All services follow **single responsibility principle** and are **independently testable**.

## MVVM Architecture

KeyPath uses a clean MVVM separation:

```
┌─────────────────────────────────────────────────┐
│                  SwiftUI Views                  │
│            (ContentView, SettingsView)          │
└─────────────────┬───────────────────────────────┘
                  │ Observes @Published properties
┌─────────────────▼───────────────────────────────┐
│              KanataViewModel                    │
│         (@ObservableObject with @Published)     │
└─────────────────┬───────────────────────────────┘
                  │ Calls methods, reads snapshots
┌─────────────────▼───────────────────────────────┐
│              KanataManager                      │
│      (Business logic, NO @ObservableObject)     │
└─────────────────┬───────────────────────────────┘
                  │ Delegates to services
┌─────────────────▼───────────────────────────────┐
│                 Services                        │
│  (Oracle, ConfigService, ProcessLifecycle...)   │
└─────────────────────────────────────────────────┘
```

**Key points:**
- **Manager** = business logic & orchestration (NOT ObservableObject)
- **ViewModel** = UI state with @Published properties
- **Views** = SwiftUI, observe ViewModel only
- **Services** = focused, reusable, independently testable

## Critical Anti-Patterns to Avoid

### 1. ❌ NEVER Bypass PermissionOracle

```swift
// ❌ BAD - Direct permission check
let hasPermission = AXIsProcessTrusted()

// ✅ GOOD - Use Oracle
let snapshot = await PermissionOracle.shared.currentSnapshot()
let hasPermission = snapshot.keyPath.accessibility.isReady
```

### 2. ❌ NEVER Add Automatic Validation Triggers

```swift
// ❌ BAD - Reactive validation (causes spam)
.onChange(of: someValue) {
    Task { await systemValidator.checkSystem() }
}

// ✅ GOOD - Explicit validation only
Button("Refresh") {
    Task { await systemValidator.checkSystem() }
}
```

**Why:** The validation refactor (ADR-008) removed reactive patterns that caused validation spam (100x improvement).

### 3. ❌ NEVER Check Permissions from Root Process

```swift
// ❌ BAD - IOHIDCheckAccess unreliable in root/daemon context
// This is why Kanata UDP reports false negatives

// ✅ GOOD - Always check from GUI context (PermissionOracle does this)
```

### 4. ❌ NEVER Create Multiple Sources of Truth

```swift
// ❌ BAD - Bypassing Oracle with direct checks
class MyView: View {
    func checkPermissions() {
        let ax = AXIsProcessTrusted() // Direct check
        let im = IOHIDCheckAccess(...) // Another direct check
    }
}

// ✅ GOOD - Single source of truth
class MyView: View {
    func checkPermissions() async {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        // Use snapshot for all permission state
    }
}
```

## Architecture Decision Records (ADRs)

KeyPath documents major architectural decisions in `CLAUDE.md`. Key ADRs:

- **ADR-001**: Oracle Pattern - Single source of truth for permissions
- **ADR-002**: State-Driven Wizard - Pure functions, deterministic navigation
- **ADR-006**: Oracle Apple API Priority - Apple APIs > TCC database
- **ADR-008**: Validation Refactor - Stateless SystemValidator (100x improvement)
- **ADR-010**: Module Split Revert - Single executable target
- **ADR-011**: Test Performance - Mock time > real sleeps (625x speedup)
- **ADR-015**: InstallerEngine Façade - Unified API for install/repair/inspect

**Before changing architecture, check for related ADRs in CLAUDE.md.**

## Common Development Tasks

### Adding a Feature

1. Check if existing services handle your needs
2. If adding to UI, use MVVM pattern (ViewModel → Manager → Services)
3. If adding new service, follow single responsibility principle
4. Write tests first (see `Tests/KeyPathTests/`)
5. Update CLAUDE.md if making architectural changes

### Debugging Issues

**Permission problems:**
```swift
// Get diagnostic snapshot
let snapshot = await PermissionOracle.shared.currentSnapshot()
print(snapshot.diagnosticSummary)
```

**Service won't start:**
```bash
# Check service status
sudo launchctl print system/com.keypath.kanata

# View logs
tail -f /var/log/kanata.log
```

**Wizard won't advance:**
- Check `WizardNavigationEngine.determineCurrentPage()` logs
- Verify issue detection in `IssueGenerator`
- Trust PermissionOracle for permission state

### Running Tests

```bash
# All tests (requires sudo)
./run-tests.sh

# Core tests only
./run-core-tests.sh

# Single test
swift test --filter TestClassName.testMethodName
```

**Test Philosophy:**
- Test YOUR code, not the language/framework
- Focus on behavior, not implementation
- Integration tests for simple features > unit tests
- No real sleeps - use mock time control

## File Organization Best Practices

### What to Edit vs. What to Leave Alone

**Safe to modify:**
- UI views (ContentView, SettingsView, etc.)
- Services (add features to existing services)
- Configuration (update config schemas)
- Tests (always safe to add tests)

**Requires careful consideration:**
- PermissionOracle (critical architecture, check ADRs first)
- WizardNavigationEngine (state-driven logic)
- KanataManager core (coordinator pattern)

**Don't touch without team discussion:**
- Core contracts/protocols (affects all consumers)
- LaunchDaemon installation logic (security-sensitive)
- TCC permission flows (months of debugging went into these)

## Privileged Helper Architecture

KeyPath uses a **hybrid approach** for privileged operations that supports both development and production workflows.

### How It Works

```
┌──────────────────────────────────────────────────────────────┐
│                    PrivilegedOperationsCoordinator           │
│                                                              │
│  #if DEBUG                        #else (RELEASE)            │
│  ┌────────────────────┐          ┌────────────────────────┐  │
│  │  Direct sudo via   │          │  XPC to KeyPathHelper  │  │
│  │  AppleScript       │          │  (root daemon)         │  │
│  │  • Multiple prompts│          │  • One-time prompt     │  │
│  │  • No cert needed  │          │  • Signed/notarized    │  │
│  └────────────────────┘          └────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| **PrivilegedOperationsCoordinator** | `Core/PrivilegedOperationsCoordinator.swift` | Routes operations to helper or sudo |
| **HelperManager** | `Core/HelperManager.swift` | App-side XPC connection manager |
| **KeyPathHelper** | `Sources/KeyPathHelper/` | Root-privileged helper binary |
| **HelperProtocol** | `Core/HelperProtocol.swift` | XPC interface (17 operations) |

### For Contributors

**You don't need a Developer ID certificate to contribute!**

In DEBUG builds (default for `swift build`), all privileged operations use direct `sudo` via AppleScript prompts. This means:
- No certificate required
- No helper binary needed
- Multiple password prompts (acceptable for development)

```bash
# Development workflow - no certificate needed
swift build
swift test
./run-tests.sh
```

### For Release Builds

Production builds embed a signed privileged helper for a professional user experience:

```bash
# Production build - requires Developer ID certificate
./build.sh
```

The helper provides:
- One-time password prompt (SMJobBless)
- Audit-token validation (rejects unauthorized XPC connections)
- 17 explicit, whitelisted operations (no generic command execution)

### Security Model

1. **Code Signing**: Both app and helper must be signed with the same Developer ID
2. **Audit-Token Validation**: Helper validates every XPC connection using `SecCodeCheckValidity`
3. **Explicit Operations Only**: No "execute arbitrary command" API
4. **On-Demand Activation**: Helper runs only when needed (not always resident as root)

**See also:** `docs/archive/HELPER.md` for implementation details.

## Build & Deployment

### Development Build

```bash
# Quick build for testing (no certificate required)
swift build

# Release build (still no certificate for local testing)
swift build -c release
```

### Production Build (TCC-Safe)

```bash
# Signed & notarized build (preserves permissions)
./Scripts/build-and-sign.sh

# Deploy to /Applications
cp -r dist/KeyPath.app /Applications/
```

**CRITICAL:** Always use signed builds in production. Unsigned builds break TCC identity and lose permissions.

### Uninstall

```bash
sudo ./Scripts/uninstall.sh
```

## Getting Help

### Documentation Resources

- `README.md` - Project overview, build instructions
- `ARCHITECTURE.md` - System design, permission hierarchy
- `CLAUDE.md` - ADRs, anti-patterns, critical architecture
- `InstallationWizard/README.md` - Wizard flow and components
- `Services/PermissionOracle.swift` - Permission detection guide
- `Managers/KanataManager.swift` - Manager extension map

### Debugging Resources

- `/var/log/kanata.log` - Kanata daemon logs
- `DiagnosticsView` in app - System diagnostics
- `PermissionOracle.diagnosticSummary` - Permission state
- `launchctl print system/com.keypath.kanata` - Service status

### Code Navigation Tips

**Finding functionality:**
- Search by keyword in Xcode/your editor
- Check service names (e.g., "KeyboardCapture" for input recording)
- Look in appropriate Manager extension (e.g., `+Lifecycle` for start/stop)
- Check wizard pages for setup-related code

**Understanding flow:**
1. Start with App.swift to see initialization
2. Follow the MVVM hierarchy (View → ViewModel → Manager → Services)
3. Check logs for runtime behavior
4. Read tests to understand expected behavior

## Next Steps

Now that you understand the architecture, here are suggested next steps:

### Week 1: Exploration
- [ ] Build and run KeyPath locally
- [ ] Read all files in the "Quick Start" section
- [ ] Run through the Installation Wizard
- [ ] Check permission states in PermissionOracle
- [ ] Explore KanataManager extension files

### Week 2: Small Changes
- [ ] Fix a small UI bug or add a minor feature
- [ ] Write tests for your changes
- [ ] Submit a PR following the guidelines in global rules (see CLAUDE.md)
- [ ] Review feedback and iterate

### Week 3: Understanding Services
- [ ] Pick one service (e.g., KeyboardCapture)
- [ ] Read its implementation completely
- [ ] Understand how it's used by KanataManager
- [ ] Write tests or improve existing tests

### Week 4: Larger Features
- [ ] Propose a feature enhancement
- [ ] Design the implementation (which services, UI changes)
- [ ] Discuss with the team
- [ ] Implement with tests
- [ ] Submit PR

## Questions?

If you're stuck or confused:

1. Check the documentation files listed above
2. Search the codebase for similar patterns
3. Check git history for context: `git log --follow <file>`
4. Ask the team - we're here to help!

## Contributing Guidelines

See `CLAUDE.md` for detailed contribution guidelines including:

- Unit testing best practices
- Documentation standards
- Pull request checklist
- Code quality standards
- Dependency management

**Golden Rule:** Test behavior, not implementation. Document outcomes, not mechanisms. Default to simple.

---

Welcome to KeyPath development! 🎉
