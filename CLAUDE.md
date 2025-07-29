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
# All tests
./run-tests.sh

# Unit tests only
swift test

# Integration tests
./test-kanata-system.sh
./test-hot-reload.sh
./test-service-status.sh
./test-installer.sh
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
- System config: `/usr/local/etc/kanata/keypath.kbd`
- Hot reload: Service restarts automatically via KanataManager

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
- **Config invalid**: Test with `kanata --cfg /usr/local/etc/kanata/keypath.kbd --check`
- **Permissions**: Grant in System Settings > Privacy & Security
- **Logs**: Check `/var/log/kanata.log`

## Code Signing

Production builds require:
- Developer ID signing
- Runtime hardening
- Notarization via `build-and-sign.sh`