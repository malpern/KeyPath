# KeyPath Architecture

This document describes the technical architecture of KeyPath, a macOS keyboard remapping application built on top of Kanata.

## Overview

KeyPath provides a user-friendly GUI for keyboard remapping on macOS, using Kanata as the underlying remapping engine. The application follows a clean architecture pattern with clear separation of concerns between UI, business logic, and system integration.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     KeyPath.app (SwiftUI)                    │
├─────────────────────────────────────────────────────────────┤
│                          ContentView                         │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  Recording  │  │   Status     │  │  Installation    │  │
│  │   Section   │  │  Messages    │  │     Wizard       │  │
│  └──────┬──────┘  └──────────────┘  └────────┬─────────┘  │
│         │                                      │             │
├─────────┴──────────────────────────────────────┴────────────┤
│                      Core Managers                           │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │KanataManager │  │  Keyboard    │  │    Lifecycle    │   │
│  │             │  │   Capture    │  │    Manager      │   │
│  └──────┬───────┘  └──────────────┘  └─────────────────┘   │
│         │                                                    │
├─────────┴────────────────────────────────────────────────────┤
│                    System Integration                        │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │  launchctl   │  │  CGEvent     │  │   FileSystem    │   │
│  │  (daemon)    │  │  (capture)   │  │   (config)      │   │
│  └──────────────┘  └──────────────┘  └─────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. User Interface Layer

#### ContentView.swift
- Main application interface
- Manages keyboard recording and mapping creation
- Displays service status and error messages
- Hosts the installation wizard

#### Installation Wizard Architecture
The installation wizard follows a modular architecture:

```
InstallationWizard/
├── Core/
│   ├── WizardTypes.swift         # Central type definitions
│   └── SystemStateDetector.swift # Pure state detection logic
├── Logic/
│   ├── WizardAutoFixer.swift     # Auto-fix capabilities
│   └── WizardNavigationEngine.swift # Navigation state machine
└── UI/
    ├── InstallationWizardView.swift # Main wizard container
    └── Pages/                    # Individual wizard pages
```

**Key Design Principles:**
- **State-Driven UI**: Single source of truth via `WizardSystemState`
- **Pure Functions**: Detection logic has no side effects
- **Protocol-Oriented**: Clean interfaces for testing
- **Separation of Concerns**: UI, logic, and detection are isolated

### 2. Business Logic Layer

#### KanataManager.swift
Central service coordinator responsible for:
- Managing the Kanata daemon lifecycle via launchctl
- Configuration file management and validation
- Permission checking (accessibility, input monitoring)
- System requirements verification
- Diagnostic collection and auto-fixing

**Key Methods:**
- `startKanata()` - Starts the daemon with safety timeout
- `saveConfiguration()` - Validates and saves key mappings
- `updateStatus()` - Polls system state
- `autoFixDiagnostic()` - Resolves common issues

#### KeyboardCapture.swift
Handles keyboard input capture using CGEvent tap:
- Single key capture for input recording
- Multi-key sequence capture for output recording
- Emergency stop monitoring (Ctrl+Space+Esc)
- Proper event handling and memory management

#### KanataLifecycleManager.swift
Manages the Kanata service lifecycle:
- Automatic recovery from crashes
- Configuration hot-reloading
- Health monitoring
- Graceful degradation

### 3. System Integration Layer

#### LaunchDaemon Architecture
```
/Library/LaunchDaemons/com.keypath.kanata.plist
└── Manages kanata process
    ├── KeepAlive: true
    ├── RunAtLoad: true
    └── Logs to: /var/log/kanata.log
```

#### File System Layout
```
~/Library/Application Support/KeyPath/
├── keypath.kbd          # User configuration
└── backups/            # Config backups

/usr/local/etc/kanata/
└── keypath.kbd         # System configuration (linked)
```

## Data Flow

### 1. Key Mapping Creation
```
User Input → KeyboardCapture → ContentView → KanataManager
                                               ↓
                                         Validate Config
                                               ↓
                                         Save to File System
                                               ↓
                                         Reload Daemon
```

### 2. System State Detection
```
SystemStateDetector → Check Conflicts
                   → Check Permissions  → Aggregate State → UI Update
                   → Check Components
```

### 3. Auto-Fix Flow
```
Detected Issue → WizardAutoFixer → Execute Fix → Verify → Update UI
```

## State Management

### Application States
The application manages several key states:

1. **Installation State** (`WizardSystemState`)
   - `initializing` - Checking system
   - `conflictsDetected` - Found conflicting processes
   - `missingPermissions` - Need user permission grants
   - `missingComponents` - Kanata/Karabiner not installed
   - `ready` - All requirements met
   - `active` - Service running

2. **Service State**
   - Running/Stopped status
   - Last error message
   - Process exit codes
   - Diagnostic issues

3. **UI State**
   - Recording status (input/output)
   - Current wizard page
   - Status messages
   - Auto-fix progress

### State Synchronization
- KanataManager polls system state every 3 seconds
- UI updates reactively via @Published properties
- Wizard monitors state changes for auto-navigation
- Emergency stop triggers immediate state updates

## Security Considerations

### Permissions Model
KeyPath requires several permissions:
1. **Input Monitoring** - For keyboard capture
2. **Accessibility** - For CGEvent tap creation
3. **Background Services** - For Launch Services integration

### Safety Features
1. **Emergency Stop** (Ctrl+Space+Esc) - Immediately stops remapping
2. **Timeout Protection** - 30-second startup timeout
3. **Validation** - Config validated before application
4. **Atomic Updates** - Config changes are atomic

## Testing Strategy

### Unit Tests
Located in `Tests/KeyPathTests/`:
- KanataManager state management
- Config validation logic
- Permission checking

### Integration Tests
Located in `Tests/InstallationWizardTests/`:
- Real system state detection
- Process management
- Permission verification
- Auto-fix operations

**Testing Philosophy:**
- Minimize mocks - test against real system
- Integration over unit tests for system interactions
- Fast feedback through focused test scopes

## Build and Distribution

### Build Process
1. **Development**: `swift build`
2. **Release**: `swift build -c release`
3. **App Bundle**: `./build.sh`
4. **Signed Release**: `./build-and-sign.sh`

### Code Signing Requirements
- Developer ID certificate for distribution
- Hardened runtime enabled
- Notarization required for Gatekeeper

## Future Considerations

### Planned Enhancements
1. **Multi-Profile Support** - Switch between mapping sets
2. **Cloud Sync** - Sync configurations across devices
3. **Visual Mapping Editor** - Drag-and-drop interface
4. **Statistics** - Track key usage patterns

### Technical Debt
1. **Error Recovery** - More granular error handling
2. **Performance** - Optimize state polling
3. **Logging** - Structured logging system
4. **Modularity** - Extract reusable components

## Contributing

When contributing to KeyPath:
1. Follow the existing architecture patterns
2. Maintain separation of concerns
3. Write integration tests for system interactions
4. Update this document for architectural changes
5. Consider safety and security implications

See CONTRIBUTING.md for detailed guidelines.