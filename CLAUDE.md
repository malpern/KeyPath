# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CURRENT SESSION STATUS (August 2024)

**COMPLETED:** Successfully transitioned to UDP-only architecture and resolved authentication issues.

**Key Fixes Applied:**
1. **UDP-Only Architecture:** Complete transition from TCP to UDP communication (commit d81d809)
2. **Secure Authentication:** Three-phase UDP authentication with session management
3. **Race Condition Fix:** Fixed UDP receive/send race conditions in client authentication
4. **Manager Consolidation:** All functionality now unified in KanataManager
5. **TCC-Safe Deployment:** Stable deployment process preserves Input Monitoring permissions

**Latest Commits:**
- Fix CI: Add missing isInitializing argument to WizardSummaryPage (80ae28f)
- Complete UDP race condition fix and architecture transition (e7a5679)
- Fix UDP authentication bug by switching to receiveMessage API (d43ac7a)

**Critical Architecture Notes:**
- **UDP Communication:** Primary communication protocol between KeyPath and Kanata
- **Secure Sessions:** Token-based authentication with session management via Keychain
- **CGEvent Integration:** KeyboardCapture service handles input recording safely
- **Bundled Kanata:** Only uses bundled kanata binary for TCC stability

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
- **KeyPath.app**: SwiftUI application for recording keypaths and managing configuration
- **LaunchDaemon**: System service (`com.keypath.kanata`) that runs Kanata
- **Configuration**: User config at `~/Library/Application Support/KeyPath/keypath.kbd`
- **System Integration**: Uses CGEvent taps for key capture and launchctl for service management

### Key Manager Classes
- `KanataManager`: **Unified manager** - handles daemon lifecycle, configuration, UI state, and user interactions
- `KeyboardCapture`: Handles CGEvent-based keyboard input recording (isolated service)
- `PermissionOracle`: **🔮 CRITICAL ARCHITECTURE** - Single source of truth for all permission detection
- `InstallationWizard/`: Multi-step setup flow with auto-fix capabilities
  - `WizardSystemState`: Single source of truth for system state
  - `SystemStateDetector`: Pure functions for state detection
  - `WizardAutoFixer`: Automated issue resolution
- `ProcessLifecycleManager`: Manages Kanata process state and recovery
- `PermissionService`: Legacy TCC database utilities (Oracle handles logic)

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
- **This commit**: ✅ Restored Apple-first hierarchy

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