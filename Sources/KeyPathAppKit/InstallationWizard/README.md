# Installation Wizard

The Installation Wizard is KeyPath's multi-step setup system that automatically detects and resolves system configuration issues. It accounts for **45% of the codebase** (17,985 lines across 44 files) due to the complexity of macOS system integration.

## Overview

The wizard handles:
- **9 pages** of guided setup
- **50+ edge cases** for macOS configuration
- **Automatic remediation** for most common issues
- **State-driven navigation** based on system detection

## Why is the Wizard So Complex?

KeyPath requires deep macOS system integration:
- TCC permissions (Accessibility, Input Monitoring, Full Disk Access)
- Karabiner-Elements VirtualHID driver installation
- LaunchDaemon service management (requires root privileges)
- Keyboard conflict detection and resolution
- UDP server configuration for Kanata communication
- Driver version compatibility (v5 for kanata v1.9.0, v6 for v1.10+)

The wizard's size reflects the **legitimate complexity** of making keyboard remapping "just work" on macOS.

## Canonical kanata Path (Permissions + Diagnostics)

KeyPath treats the **system-installed kanata binary** as the canonical identity for TCC permissions:

- `kanata`: `/Library/KeyPath/bin/kanata`

The app bundle copy is **installer payload**. If the daemon executes a different path than the wizard instructs users to add, macOS will treat them as different identities and permissions can appear “green” while remapping fails.

## Architecture

```
InstallationWizard/
├── Core/                 # Business logic (25 files, ~12,000 lines)
│   ├── State Management  # Navigation, state machine, issue detection
│   ├── Installation      # Daemon, driver, package installation
│   └── Remediation       # Auto-fixing, permission coordination
├── UI/                   # Views (14 files, ~5,500 lines)
│   ├── InstallationWizardView.swift  # Main container
│   ├── WizardDesignSystem.swift      # Design tokens & styling
│   └── Pages/                        # Individual wizard pages
└── Components/           # Reusable UI (5 files, ~500 lines)
```

## The 9-Page Flow

The wizard uses **state-driven navigation** - pages are shown dynamically based on detected issues:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         1. SUMMARY PAGE                             │
│  Overview of system status and required setup steps                │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                   2. FULL DISK ACCESS (Optional)                    │
│  Improves diagnostics - shown once if not blocking                 │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                    3. RESOLVE CONFLICTS (Blocking)                  │
│  Detects conflicting processes (Karabiner-Grabber, orphaned Kanata) │
│  Auto-fix: Terminates conflicts or adopts managed processes         │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                 4. INPUT MONITORING PERMISSION                      │
│  Required for both KeyPath (recording) and Kanata (remapping)      │
│  User action: Opens System Settings                                │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                  5. ACCESSIBILITY PERMISSION                        │
│  Required for Kanata's keyboard event injection                    │
│  User action: Opens System Settings                                │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│              6. KARABINER COMPONENTS (Blocking)                     │
│  Installs: VirtualHID Driver, VirtualHID Manager, VirtualHID Daemon│
│  Auto-fix: Downloads/installs missing components, handles versions │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                7. KANATA COMPONENTS (Blocking)                      │
│  Installs: Bundled Kanata binary, LaunchDaemon services            │
│  Auto-fix: Copies signed binary, configures LaunchDaemon           │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                      8. START SERVICE                               │
│  Starts the Kanata LaunchDaemon service                            │
│  Auto-fix: launchctl kickstart                                     │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                  9. COMMUNICATION (Optional)                        │
│  Configures UDP server for config hot-reload                       │
│  Auto-fix: Generates auth token, updates service config            │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
                            ✓ COMPLETE
```

### Navigation Priority

Pages are shown in priority order when issues are detected:

1. **Conflicts** (highest) - Must resolve before anything else
2. **Permissions** - Input Monitoring, then Accessibility
3. **Communication** - UDP server configuration (optional but recommended)
4. **Karabiner Components** - Driver and VirtualHID setup
5. **Kanata Components** - Binary and service installation
6. **Service** - Starting the keyboard remapping service
7. **Full Disk Access** - Shown once if no blocking issues
8. **Summary** - Default when no issues detected

## Core Components

### State Management (Navigation & Detection)

| File | Lines | Purpose |
|------|-------|---------|
| `WizardNavigationEngine.swift` | 376 | **Core navigation logic** - Determines current page from system state and issues |
| `WizardStateMachine.swift` | 248 | **State definitions** - WizardSystemState enum and transitions |
| `WizardStateManager.swift` | 485 | **State coordination** - Manages wizard lifecycle and page transitions |
| `IssueGenerator.swift` | 312 | **Issue detection** - Converts system problems into WizardIssue objects |
| `WizardTypes.swift` | 433 | **Type definitions** - All wizard enums, structs, protocols (see Type Reference below) |

### Installation & Remediation

| File | Lines | Purpose |
|------|-------|---------|
| `WizardAutoFixer.swift` | 1,187 | **Auto-remediation** - Implements fixes for 50+ edge cases |
| `InstallerEngine.swift` | 400 | **Service installation façade** - install/repair/uninstall through recipes |
| `VHIDDeviceManager.swift` | 548 | **Driver management** - VirtualHID driver download, installation, version checking |
| `PackageManager.swift` | 650 | **Dependency installation** - Homebrew and .pkg installer integration |
| `PermissionGrantCoordinator.swift` | 428 | **Permission flows** - Coordinates System Settings dialogs and permission grants |

### System Integration

| File | Lines | Purpose |
|------|-------|---------|
| `SystemValidator.swift` | 269 | **System validation** - Stateless, defensive system checks (no caching) |
| `DriverCompatibilityChecker.swift` | 145 | **Version compatibility** - Checks Karabiner driver vs. kanata version |
| `ConflictResolver.swift` | 289 | **Conflict resolution** - Detects and terminates conflicting processes |

## Key Types Reference

All wizard types are defined in `WizardTypes.swift` (433 lines):

### Pages (`WizardPage` enum)
- `summary`, `fullDiskAccess`, `conflicts`, `inputMonitoring`, `accessibility`
- `communication`, `karabinerComponents`, `kanataComponents`, `service`

### System State (`WizardSystemState` enum)
- `initializing`, `conflictsDetected`, `missingPermissions`, `missingComponents`
- `daemonNotRunning`, `serviceNotRunning`, `ready`, `active`

### Issues (`WizardIssue` struct)
- Structured issue representation with severity, category, auto-fix action
- Categories: `conflicts`, `permissions`, `backgroundServices`, `installation`, `daemon`, `systemRequirements`
- Severities: `info`, `warning`, `error`, `critical`

### Auto-Fix Actions (`AutoFixAction` enum)
- 16 different auto-fix capabilities (see WizardTypes.swift:151-172)
- Examples: `terminateConflictingProcesses`, `installMissingComponents`, `fixDriverVersionMismatch`

### Requirements
- `SystemConflict` - Conflicting processes (Karabiner-Grabber, orphaned Kanata, etc.)
- `PermissionRequirement` - TCC permissions (Input Monitoring, Accessibility, FDA)
- `ComponentRequirement` - System components (drivers, binaries, services)

## How State-Driven Navigation Works

The wizard uses `WizardNavigationEngine.determineCurrentPage()` to calculate the correct page:

```swift
// Priority-based navigation (see WizardNavigationEngine.swift:19-149)
1. Check for conflicts → .conflicts
2. Check for permission issues → .inputMonitoring or .accessibility
3. Check for communication issues → .communication
4. Check for Karabiner issues → .karabinerComponents
5. Check for Kanata issues → .kanataComponents
6. Check service state → .service
7. Show Full Disk Access once → .fullDiskAccess (if not shown and no blocking issues)
8. Default → .summary (all clear)
```

This ensures users always see the **most critical issue first** without manual navigation.

## Design System

The wizard uses `WizardDesignSystem.swift` (959 lines) for consistent styling:

- **Colors**: Status indicators, semantic colors, glass effects
- **Typography**: Heading styles, body text, captions
- **Spacing**: Consistent padding, margins, gaps
- **Components**: Buttons, cards, status badges, progress indicators

## UI Architecture

```
InstallationWizardView.swift (1,020 lines)
├── Header (title, close button)
├── Page Content (dynamic based on currentPage)
│   ├── WizardSummaryPage
│   ├── WizardFullDiskAccessPage
│   ├── WizardConflictsPage
│   ├── WizardInputMonitoringPage
│   ├── WizardAccessibilityPage
│   ├── WizardKarabinerComponentsPage
│   ├── WizardKanataComponentsPage
│   ├── WizardServicePage
│   └── WizardCommunicationPage
├── Page Dots (navigation indicators)
└── Action Buttons (Next, Previous, Fix)
```

Each page is 400-600 lines and follows a consistent pattern:
1. Status detection
2. Issue presentation
3. Auto-fix button (if available)
4. Manual instructions (if user action required)
5. Hover tooltips (added October 2025)

## Testing Strategy

### Core Logic Tests
- `WizardNavigationEngineTests.swift` - Page navigation logic
- `WizardStateMachineTests.swift` - State transitions
- `SystemValidatorTests.swift` - System validation (defensive assertions)

### Integration Tests
- Wizard triggering from main app
- Auto-fix action execution
- Permission grant coordination

## Common Development Tasks

### Adding a New Wizard Page
1. Add case to `WizardPage` enum in `WizardTypes.swift`
2. Update `WizardPage.orderedPages` array
3. Add navigation logic in `WizardNavigationEngine.determineCurrentPage()`
4. Create page view in `UI/Pages/`
5. Add to `InstallationWizardView` content switch

### Adding a New Auto-Fix Action
1. Add case to `AutoFixAction` enum in `WizardTypes.swift`
2. Implement fix in `WizardAutoFixer.performAutoFix()`
3. Add issue generation in `IssueGenerator`
4. Update navigation logic if needed

### Adding a New Issue Type
1. Add requirement to appropriate enum (`SystemConflict`, `PermissionRequirement`, `ComponentRequirement`)
2. Add detection logic in `SystemValidator`
3. Generate `WizardIssue` in `IssueGenerator`
4. Map to page in `WizardNavigationEngine`

## Architecture Decisions

- **ADR-002**: State-Driven Wizard - Pure functions for detection, deterministic navigation
- **ADR-008**: Validation Refactor - Stateless SystemValidator with defensive assertions
- **ADR-012**: Karabiner Driver Version - Version compatibility detection (v5 for kanata v1.9.0)

## Known Issues & Future Work

### ✅ Completed (November 2025)
- **ADR-012**: Driver version detection fully wired to Fix button
  - Detection: `VHIDDeviceManager.hasVersionMismatch()` → `SystemContext.components.vhidVersionMismatch`
  - Action: `ActionDeterminer` adds `.fixDriverVersionMismatch` when version mismatch detected
  - Dialog: `WizardAutoFixer.fixDriverVersionMismatch()` shows confirmation dialog
  - Install: Downloads and installs v5.0.0 via `PrivilegedOperationsCoordinator`

### Pending Work
- ✅ DONE: Updated `requiredDriverVersionMajor` to 6 in VHIDDeviceManager.swift (Kanata v1.10.0 released Nov 2025)
- ✅ DONE: Missing bundled kanata binary now surfaces as .critical wizard issue (Nov 2025)

### Future Improvements
- Consolidate 25 Core files into logical subdirectories (StateManagement/, Installation/, Remediation/)
- Extract `WizardTypes.swift` into focused files (WizardPageState.swift, WizardIssues.swift, WizardActions.swift)
- Add more hover tooltips for user guidance

## Getting Started

### For New Developers
1. Start with `WizardNavigationEngine.swift` - understand the page flow
2. Read `WizardTypes.swift` - learn all the type definitions
3. Look at one page (e.g., `WizardInputMonitoringPage.swift`) - see the pattern
4. Check `WizardAutoFixer.swift` - understand auto-remediation
5. Review `ARCHITECTURE.md` - system-level design decisions

### Quick Debugging
- **Wizard won't advance**: Check `WizardNavigationEngine.determineCurrentPage()` logs
- **Auto-fix fails**: Look at `WizardAutoFixer.performAutoFix()` return value
- **Permissions incorrect**: Trust `PermissionOracle` (see `Sources/KeyPathPermissions/PermissionOracle.swift`)
- **Service won't start**: Check `/var/log/kanata.log` and `launchctl print system/com.keypath.kanata`

## Related Documentation

- `../ARCHITECTURE.md` - Overall system design
- `../CLAUDE.md` - ADRs, anti-patterns, critical architecture
- `Services/PermissionOracle.swift` - Single source of truth for permissions
- `Managers/KanataManager.swift` - Main service coordinator
