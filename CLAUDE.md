# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KeyPath is a macOS application that provides keyboard remapping using Kanata as the backend engine. It features a SwiftUI frontend and a LaunchDaemon architecture for reliable system-level key remapping.

## Architecture

### Components
- **KeyPath.app**: SwiftUI application for recording keypaths and managing configuration
- **LaunchDaemon**: System service (`com.keypath.kanata`) that runs Kanata
- **File-based config**: Updates via `/usr/local/etc/kanata/keypath.kbd`

### Critical Files
- `Sources/KeyPath/KanataManager.swift`: Service management via launchctl
- `Sources/KeyPath/KeyboardCapture.swift`: CGEvent-based key recording
- `Sources/KeyPath/InstallationWizardView.swift`: Multi-step installation flow

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
# Automated tests (with passwordless sudo setup)
./run-tests-automated.sh

# All tests (manual password entry)
./run-tests.sh

# Unit tests only
swift test

# Integration tests
./test-kanata-system.sh
./test-hot-reload.sh
./test-service-status.sh
./test-installer.sh
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

## System Installation

```bash
# Install LaunchDaemon service
sudo ./install-system.sh

# Uninstall everything
sudo ./uninstall.sh
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
1. Run code formatting and linting
2. Build the release version
3. **SKIP TESTS** unless explicitly requested (e.g., "run tests", "test before deploying")
4. Create the app bundle
5. Sign and notarize (if applicable)
6. Install to /Applications

This speeds up deployment by avoiding the test suite which can be time-consuming.