# New Developer Guide

Welcome to KeyPath! This guide covers what you need to know to start contributing.

## What is KeyPath?

KeyPath is a macOS keyboard remapping app built on [Kanata](https://github.com/jtroo/kanata). It provides a SwiftUI interface for creating keyboard remappings without editing config files.

**Key features:**
- Visual rule editor (press-to-record)
- Installation wizard (handles permissions, drivers, services)
- System-level remapping via LaunchDaemon
- Real-time config updates

## Quick Start

### 1. Build and Run

```bash
# Clone the repo
git clone https://github.com/malpern/KeyPath.git
cd KeyPath

# Build (no certificate needed for development)
swift build

# Run tests
swift test

# Build app bundle
./Scripts/build.sh
```

### 2. Read These First

1. **[README.md](../README.md)** - Project overview and build instructions
2. **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design overview
3. **[CLAUDE.md](../CLAUDE.md)** - Architecture patterns and ADRs (read when needed)
4. **This guide** - What you're reading now

### 3. Key Files to Understand

- `Sources/KeyPathApp/Main.swift` - Entry point (dispatches CLI or GUI)
- `Sources/KeyPathAppKit/App.swift` - SwiftUI app definition
- `Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift` - Main coordinator (business logic)
- `Sources/KeyPathAppKit/UI/ViewModels/KanataViewModel.swift` - UI state (MVVM)
- `Sources/KeyPathAppKit/Services/PermissionOracle.swift` - Permission detection (CRITICAL)
- `Sources/KeyPathAppKit/InstallationWizard/` - Setup wizard (45% of codebase)

## Core Architecture (Simplified)

```
SwiftUI Views → KanataViewModel → RuntimeCoordinator → Services
```

**Key concepts:**
- **RuntimeCoordinator**: Business logic (NOT ObservableObject)
- **KanataViewModel**: UI state with @Published properties (ObservableObject)
- **Services**: Focused, reusable components (PermissionOracle, ConfigurationService, etc.)
- **InstallerEngine**: Unified API for installation/repair operations

**For details:** See [ARCHITECTURE.md](ARCHITECTURE.md)

## Critical Rules (Don't Break These)

### 1. Always Use PermissionOracle

```swift
// ❌ BAD - Never do this
let hasPermission = AXIsProcessTrusted()

// ✅ GOOD - Always use Oracle
let snapshot = await PermissionOracle.shared.currentSnapshot()
let hasPermission = snapshot.keyPath.accessibility.isReady
```

**Why:** PermissionOracle is the single source of truth. Bypassing it causes inconsistent UI state.

### 2. Don't Use KanataManager for Installation

```swift
// ❌ BAD - Wrong tool for the job
await kanataManager.install()

// ✅ GOOD - Use InstallerEngine
let engine = InstallerEngine()
let report = await engine.run(intent: .install, using: broker)
```

**Why:** RuntimeCoordinator handles runtime operations. InstallerEngine handles installation/repair.

### 3. No Automatic Validation Triggers

```swift
// ❌ BAD - Causes validation spam
.onChange(of: someValue) {
    Task { await systemValidator.checkSystem() }
}

// ✅ GOOD - Explicit only
Button("Refresh") {
    Task { await systemValidator.checkSystem() }
}
```

**Why:** Validation is expensive. Only trigger when user explicitly requests it.

### 4. Never Check Permissions from Root Process

```swift
// ❌ BAD - Unreliable in daemon context
// Root processes can't self-report TCC status accurately

// ✅ GOOD - Always check from GUI context
// PermissionOracle does this automatically
```

## Common Tasks

### Adding a Feature

1. **Check existing services** - Does a service already handle this?
2. **Follow MVVM pattern** - View → ViewModel → RuntimeCoordinator → Services
3. **Write tests** - See `Tests/KeyPathTests/`
4. **Update docs** - Add to CLAUDE.md if architectural change

### Debugging

**Permission issues:**
```swift
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
- Trust PermissionOracle for permission state

### Running Tests

```bash
# All tests
swift test

# Single test
swift test --filter TestClassName.testMethodName

# Core tests only
./run-core-tests.sh
```

**Test philosophy:**
- Test behavior, not implementation
- No real sleeps - use mock time control
- Integration tests > unit tests for simple features

## File Organization

**Safe to modify:**
- UI views (ContentView, SettingsView, etc.)
- Services (add features to existing services)
- Tests (always safe to add)

**Requires careful consideration:**
- PermissionOracle (critical architecture - check ADRs first)
- RuntimeCoordinator core (coordinator pattern)
- WizardNavigationEngine (state-driven logic)

**Don't touch without discussion:**
- Core contracts/protocols (affects all consumers)
- LaunchDaemon installation logic (security-sensitive)
- TCC permission flows (months of debugging)

## Where to Find More Info

**Architecture:**
- [ARCHITECTURE.md](ARCHITECTURE.md) - System design
- [ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md) - Visual diagrams
- [CLAUDE.md](../CLAUDE.md) - ADRs and patterns

**Code:**
- `Sources/KeyPathAppKit/InstallationWizard/README.md` - Wizard details
- `Sources/KeyPathAppKit/Services/PermissionOracle.swift` - Permission guide (in file comments)
- `Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift` - Coordinator guide (in file comments)

**Debugging:**
- `/var/log/kanata.log` - Kanata daemon logs
- `DiagnosticsView` in app - System diagnostics
- `launchctl print system/com.keypath.kanata` - Service status

## Next Steps

1. **Build and run** the app locally
2. **Read** the files listed in "Key Files to Understand"
3. **Pick a small task** (UI bug fix, minor feature)
4. **Write tests** for your changes
5. **Submit a PR** following the guidelines in [CLAUDE.md](../CLAUDE.md)

## Questions?

- Check the documentation files listed above
- Search the codebase for similar patterns
- Check git history: `git log --follow <file>`
- Ask the team - we're here to help!

---

**Golden Rule:** Test behavior, not implementation. Document outcomes, not mechanisms. Default to simple.

Welcome to KeyPath development! 🎉
