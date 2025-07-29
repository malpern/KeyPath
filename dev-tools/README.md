# Development Tools

This directory contains development and debugging utilities for KeyPath.

## Debug Scripts

- **debug-conflict-detection.swift** - Debug process conflicts
- **debug-conflict-pgrep.swift** - Debug pgrep-based conflict detection  
- **debug-permissions.swift** - Debug system permissions

## Test Scripts

- **test-permissions.swift** - Test permission checking
- **test-updated-conflict.swift** - Test conflict detection updates
- **test-wizard-ui.swift** - Test installation wizard UI

## Usage

These tools are for development and debugging only. Run them directly with Swift:

```bash
swift dev-tools/debug-permissions.swift
```