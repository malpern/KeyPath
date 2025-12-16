# KeyPath Architecture Guide

## System Overview

KeyPath is a native macOS application that simplifies the usage of the powerful [Kanata](https://github.com/jtroo/kanata) keyboard remapping engine. It acts as a bridge between the user and the low-level system requirements of keyboard interception on macOS.

### High-Level Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           KeyPath.app (User UI)                         │
│                                                                         │
│  ┌─────────────────┐  ┌──────────────┐  ┌─────────────────────────────┐ │
│  │   Recording UI  │  │   Settings   │  │     Installation Wizard     │ │
│  └─────────────────┘  └──────────────┘  └─────────────────────────────┘ │
│           │                  │                        │                 │
└───────────┼──────────────────┼────────────────────────┼─────────────────┘
            │                  │                        │
            ▼                  ▼                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        System Integration Layer                         │
│                                                                         │
│  ┌─────────────────┐  ┌────────────────────┐  ┌──────────────────────┐  │
│  │ PermissionOracle│  │ RuntimeCoordinator │  │    InstallerEngine   │  │
│  │ (Truth Source)  │  │ (Service Control)  │  │   (Setup Façade)     │  │
│  └─────────────────┘  └────────────────────┘  └──────────────────────┘  │
│                        │                                              │
│                        ▼                                              │
│              ┌─────────────────────┐                                  │
│              │  KanataViewModel    │                                  │
│              │  (MVVM UI Layer)     │                                  │
│              └─────────────────────┘                                  │
└───────────┬──────────────────┬────────────────────────┬─────────────────┘
            │                  │                        │
            ▼                  ▼                        ▼
┌──────────────────────────────┐ ┌──────────────────────────────┐ ┌────────────────────┐
│ com.keypath.kanata (Agent)   │ │ Karabiner VirtualHID Services │ │    MacOS TCC API   │
│ (SMAppService + TCP + IM)    │ │ (LaunchDaemons, root)         │ │ (Security Frame)   │
└──────────────────────────────┘ └──────────────────────────────┘ └────────────────────┘
```

## Core Architectural Principles

### 1. PermissionOracle: Single Source of Truth
KeyPath uses a dedicated Actor, `PermissionOracle`, to manage the complex state of macOS permissions.
*   **Apple APIs First**: We trust `IOHIDCheckAccess` from the GUI context as the authoritative source.
*   **TCC Fallback**: We query the TCC database only when Apple APIs return "Unknown", typically during initial setup chicken-and-egg scenarios.
*   **Caching**: Results are cached for ~1.5s to balance UI responsiveness with system load.
*   **Principle**: Never bypass the Oracle. If the Oracle says permission is denied, the UI must reflect that, even if other heuristics suggest otherwise.

### 2. RuntimeCoordinator: Service Orchestration
The `RuntimeCoordinator` orchestrates Kanata process lifecycle and configuration management.
*   **Business Logic Layer**: Handles all runtime operations (start/stop/restart, config management, TCP communication).
*   **Not ObservableObject**: Keeps business logic independent of SwiftUI reactivity.
*   **State Snapshots**: Provides `getCurrentUIState()` for ViewModel synchronization.
*   **Extension-Based Architecture**: Split across multiple files (~2,820 lines total) organized by concern (Lifecycle, Configuration, Engine, EventTaps, Output).
*   **MVVM Separation**: UI state is handled by `KanataViewModel`, which observes coordinator state changes.

### 3. KanataViewModel: MVVM UI Layer
The `KanataViewModel` provides a thin adapter between SwiftUI views and `RuntimeCoordinator`.
*   **ObservableObject**: Owns all `@Published` properties for SwiftUI reactivity.
*   **Thin Adapter**: No business logic—delegates all actions to `RuntimeCoordinator`.
*   **Event-Driven Updates**: Observes coordinator state changes via `AsyncStream` (not polling).
*   **Separation of Concerns**: Keeps UI reactivity separate from business logic.

### 4. InstallerEngine: The Setup Façade
The `InstallerEngine` provides a unified, declarative API for all installation, repair, and uninstall operations.
*   **Declarative API**: `run(intent: .install)` handles everything.
*   **State-Driven Planning**: `inspectSystem()` -> `makePlan()` -> `execute()`.
*   **Recipe-Based Execution**: Atomic `ServiceRecipe` units ensure consistent operations.
*   **Unified Reporting**: Returns structured `InstallerReport` for UI and logging.
*   **Supersedes**: Replaces ad-hoc logic in `WizardAutoFixer` and direct manager calls.

### 5. State-Driven Installation Wizard
The installation wizard is not a linear script but a state machine.
*   **Pure Function Detection**: `SystemValidator` examines the system state (permissions, drivers, processes) without side effects.
*   **Stateless Design**: No caching—returns fresh state on each call (Oracle provides its own 1.5s cache).
*   **Deterministic Navigation**: `WizardNavigationEngine` maps the detected state + current issues to the exact page the user needs to see.
*   **Auto-Fixer**: Atomic, idempotent actions (e.g., `restartVirtualHIDDaemon`) resolve specific issues without brittle scripting.

### 6. Service Architecture (SMAppService Agent + LaunchDaemons)
KeyPath uses a user-session runtime for kanata, plus root-level VirtualHID services:
*   **Kanata Service (SMAppService Agent)**: `com.keypath.kanata` is registered via `SMAppService.agent`.
    It runs in the logged-in user session so Input Monitoring can apply.
*   **Stable Kanata Binary Path**: The agent execs `/Library/KeyPath/bin/kanata`.
    Input Monitoring for CLI tools is path-specific.
    Standardizing the path prevents “granted but broken” states across updates/dev builds.
*   **VirtualHID Services (LaunchDaemons)**: Separate launchd services install, enable, and monitor Karabiner’s VirtualHID daemon and manager.
    These remain system-level and may require admin approval.
*   **Why This Model?**: System LaunchDaemons can appear “granted” in TCC but still fail to receive real key events.
    KeyPath requires runtime evidence that kanata is processing real key events before showing the system as ready.

### 7. Process Lifecycle Management
We use a `PID file` strategy to track ownership of the `kanata` process.
*   **Ownership**: We write a PID file when we start `kanata`.
*   **Conflict Detection**: We check for running `kanata` processes that *don't* match our PID. These are flagged as "external conflicts" (e.g., a user running `kanata` in a terminal).
*   **Recovery**: On startup, we check for orphaned PID files or processes and clean them up.

## Critical Implementation Details

### Permission Checking
We check permissions from the **GUI context** (User Session), not the Root Daemon context.
*   **Reason**: macOS `root` processes often cannot self-report TCC status accurately due to "responsible process" inheritance rules.
*   **Pattern**: The UI detects the TCC grant for the active kanata binary path,
    then validates that the running kanata process is actually receiving real key events.

### Inter-Process Communication (IPC)
Communication between the UI and the `com.keypath.kanata` agent happens via **TCP**.
*   **Protocol**: Lightweight JSON payloads over TCP port 37001.
*   **Performance**: < 100ms latency for status updates.
*   **Usage**: Sending config reloads, receiving "heartbeat" status updates.
*   **Security**: Localhost-only binding.

## Project Structure

*   `Sources/KeyPathApp`: App executable entry point (Main.swift, Info.plist, resources).
*   `Sources/KeyPathAppKit`: Main app code (shared library) containing UI, managers, services, and business logic.
*   `Sources/KeyPathCLI`: Standalone CLI executable entry point.
*   `Sources/KeyPathCore`: Shared core utilities (Logger, FeatureFlags, TestEnvironment, SubprocessRunner).
*   `Sources/KeyPathHelper`: Privileged helper tool for admin tasks (XPC + SMJobBless).
*   `Sources/KeyPathPermissions`: PermissionOracle actor for permission detection.
*   `Sources/KeyPathDaemonLifecycle`: Service management and PID logic (ProcessLifecycleManager, PIDFileManager).
*   `Sources/KeyPathWizardCore`: Wizard shared types (SystemSnapshot, WizardTypes).
*   `Scripts/`: Build, test, and maintenance scripts.

## Visual Architecture Diagram

For a detailed visual guide to component relationships and data flow, see:
**[Architecture Diagram](ARCHITECTURE_DIAGRAM.md)** - Mermaid diagrams showing:
- System overview with all components
- Data flow sequences (key mapping, installation wizard)
- Component responsibilities
- Entry points for common tasks

## Privileged Helper Architecture

KeyPath uses a **hybrid approach** to privileged operations that supports both development and production workflows.

### Runtime Detection Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                     KeyPath Architecture                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────┐        ┌──────────────────────┐  │
│  │   DEBUG BUILDS       │        │  RELEASE BUILDS      │  │
│  │  (Contributors)      │        │  (End Users)         │  │
│  ├──────────────────────┤        ├──────────────────────┤  │
│  │                      │        │                      │  │
│  │  KeyPath.app         │        │  KeyPath.app         │  │
│  │       ↓              │        │       ↓              │  │
│  │  Direct sudo         │        │  Privileged Helper   │  │
│  │  (AppleScript)       │        │  (XPC + SMJobBless)  │  │
│  │       ↓              │        │       ↓              │  │
│  │  System Operations   │        │  System Operations   │  │
│  │                      │        │                      │  │
│  │  • Multiple prompts  │        │  • One-time prompt   │  │
│  │  • No cert needed    │        │  • Signed/notarized  │  │
│  │  • Easy testing      │        │  • Professional UX   │  │
│  │                      │        │                      │  │
│  └──────────────────────┘        └──────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

*   **`PrivilegedOperationsCoordinator`**: Central façade that routes operations to either helper or sudo based on build mode.
*   **`HelperManager`**: App-side XPC connection manager with async/await wrappers.
*   **`KeyPathHelper`**: Root-privileged helper binary installed via SMJobBless.
*   **`HelperProtocol`**: XPC interface defining 17 privileged operations.

### Security Model

1. **Audit-Token Validation**: Helper validates every XPC connection using `SecCodeCheckValidity`.
2. **Code Signing Requirements**: Both app and helper must be signed with the same Developer ID certificate.
3. **Explicit Operations Only**: No generic "execute command" API—only 17 whitelisted operations.
4. **On-Demand Activation**: Helper runs only when needed (not always resident as root).

### Build Workflows

**Development (Contributors):**
```bash
swift build          # No certificate required
swift test           # Uses direct sudo path
```

**Production (Releases):**
```bash
./build.sh           # Builds, signs, embeds helper, notarizes
```

For detailed implementation, see `docs/archive/HELPER.md`.

## Release Milestones

KeyPath uses feature gating via `ReleaseMilestone` enum in `FeatureFlags.swift` to control which features are available in each release:

### R1: Installer + Custom Rules (Current Release)

**Core Components:**
- **InstallerEngine**: Primary façade for installation/repair/uninstall operations
- **PermissionOracle**: Single source of truth for permission detection
- **RuntimeCoordinator**: Service orchestration and lifecycle management
- **KanataViewModel**: MVVM UI layer with @Published properties
- **ConfigurationService**: Config file I/O and validation
- **Custom Rules**: User-defined key mappings with Tap-Hold & Tap-Dance support

**Features:**
- Installation Wizard with auto-remediation
- LaunchDaemon service management
- Privileged Helper (SMAppService)
- Custom Rules editor
- Config generation and hot reload
- Action URI system (launch, layer, rule, notify, open, fakekey)

**Not Included:**
- Rule Collections (Vim, Caps Lock, Home Row Mods, etc.)
- Live Keyboard Overlay
- Mapper UI
- Simulator Tab
- Virtual Keys Inspector

### R2: Full Features (Future Release)

Adds to R1:
- **RuleCollectionsManager**: Pre-built rule sets
- **Overlay System**: Live keyboard visualization
- **Mapper UI**: Graphical keyboard layout editor
- **Simulator**: Test configs without applying them
- **Virtual Keys Inspector**: UI for viewing/testing virtual keys

**Technical Details:**
- R1 uses thin Kanata fork (~480 lines)
- R2 uses full Kanata fork (~700 lines)
- Secret toggle: `Ctrl+Option+Cmd+R` cycles milestones at runtime (development only)

## Development Guidelines

1.  **Logging**: Use `AppLogger`. Start logs with emojis for readability (🚀 start, ✅ success, ❌ error).
2.  **Concurrency**: Use Swift 6 concurrency (`async`/`await`, `Actor`). Avoid completion handlers.
3.  **Tests**: Run `./test.sh` before committing. Do not use `sudo` in tests; mock the system environment.
4.  **Privileged Operations**: Always use `PrivilegedOperationsCoordinator`—never call `launchctl` or `sudo` directly.
