# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KeyPath is a macOS application that provides keyboard remapping using Kanata as the backend engine. It features a SwiftUI frontend and a LaunchDaemon architecture for reliable system-level key remapping.

## Architecture

### Core Components
- **KeyPath.app**: SwiftUI application for recording keypaths and managing configuration
- **LaunchDaemon**: System service (`com.keypath.kanata`) that runs Kanata
- **Configuration**: User config at `~/Library/Application Support/KeyPath/keypath.kbd`
- **System Integration**: Uses CGEvent taps for key capture and launchctl for service management

### Key Manager Classes
- `KanataManager`: Central service coordinator, manages daemon lifecycle and configuration
- `KeyboardCapture`: Handles CGEvent-based keyboard input recording
- `InstallationWizard/`: Multi-step setup flow with auto-fix capabilities
- `ProcessLifecycleManager`: Manages Kanata process state and recovery
- `PermissionService`: Handles accessibility and input monitoring permissions

## Build Commands

```bash
# Development build
swift build

# Release build
swift build -c release

# Production build with app bundle
./build.sh

# Signed & notarized build  
./build-and-sign.sh
```

## Test Commands

```bash
# Run a single test
swift test --filter TestClassName.testMethodName

# Unit tests only
swift test

# Automated tests (with passwordless sudo setup)
./run-tests-automated.sh

# All tests (manual password entry)
./run-tests.sh

# Individual integration tests
./test-kanata-system.sh   # Tests Kanata service operations
./test-hot-reload.sh      # Tests config hot-reload functionality
./test-service-status.sh  # Tests service status detection
./test-installer.sh       # Tests installation wizard
```

### Automated Testing Setup

For CI/CD or frequent testing, use the automated test runner:

```bash
# Interactive setup (asks for confirmation)
./run-tests-automated.sh

# Automatic setup (for CI)
KEYPATH_TESTING=true ./run-tests-automated.sh

# Or with flag
./run-tests-automated.sh --auto-setup
```

The automated runner:
1. Sets up passwordless sudo for specific KeyPath test commands
2. Runs all tests without password prompts
3. Cleans up the sudo configuration afterward

**Manual sudo setup for development:**
```bash
# Setup passwordless sudo for testing
./Scripts/setup-test-sudoers.sh

# Run tests (no passwords required)
swift test

# Cleanup when done
./Scripts/cleanup-test-sudoers.sh
```

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
```

### Configuration
- User config: `~/Library/Application Support/KeyPath/keypath.kbd`
- Hot reload: Service restarts automatically via KanataManager when config changes

## Dependencies

- **Kanata**: Keyboard remapping engine (install via `brew install kanata`)
- **Location**: `/opt/homebrew/bin/kanata` (ARM) or `/usr/local/bin/kanata` (Intel)
- **macOS 13.0+**
- **Permissions**: Accessibility (app) + Input Monitoring (kanata binary)

## Kanata Config Format

```lisp
(defcfg
  process-unmapped-keys yes
)

(defsrc caps)
(deflayer base esc)
```

## Key Mapping

KanataManager handles special key conversions:
- `caps` → Caps Lock
- `space` → Space  
- `tab` → Tab
- `escape` → Escape
- `return` → Return
- `delete` → Backspace
- Multi-char outputs → Macro sequences

## Troubleshooting

- **Service won't start**: Check kanata path with `which kanata`
- **Config invalid**: Test with `kanata --cfg "~/Library/Application Support/KeyPath/keypath.kbd" --check`
- **Permissions**: Grant in System Settings > Privacy & Security
- **Logs**: Check `/var/log/kanata.log`

## Code Signing

Production builds require:
- Developer ID signing
- Runtime hardening
- Notarization via `build-and-sign.sh`

## Deployment Instructions

When asked to deploy or prepare for deployment:
1. Format code with Swift formatter (if SwiftFormat is available)
2. Fix linting issues with SwiftLint (if available): `swiftlint --fix --quiet`
3. Build the release version: `swift build -c release`
4. **SKIP TESTS** unless explicitly requested (e.g., "run tests", "test before deploying")
5. Create app bundle: `./Scripts/build.sh`
6. Sign and notarize (if signing identity available): `./Scripts/build-and-sign.sh`
7. Install to /Applications: `cp -r build/KeyPath.app /Applications/`

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