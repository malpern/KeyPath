---
layout: default
title: Architecture Overview
description: System design and architecture of KeyPath
---

# Architecture Overview

KeyPath is built on a clean, modular architecture that separates concerns and ensures reliability.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  KeyPath.app (SwiftUI)                                      │
│  - User interface                                           │
│  - Visual key recording                                    │
│  - Configuration management                                 │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  InstallerEngine (Façade)                                   │
│  - Unified entry point for all system operations           │
│  - Installation, repair, uninstall                         │
│  - System inspection                                       │
└─────────────────────────┬───────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
        ▼                                   ▼
┌──────────────────┐              ┌──────────────────┐
│  LaunchDaemon    │              │  KanataManager   │
│  - Service mgmt  │              │  - Runtime coord │
│  - Permissions   │              │  - TCP client    │
└──────────────────┘              └──────────────────┘
        │                                   │
        └─────────────────┬─────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Kanata (Rust)                                              │
│  - Keyboard remapping engine                                │
│  - TCP server for communication                             │
│  - Config hot-reload                                        │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### InstallerEngine

The **InstallerEngine** is the unified façade for all system operations. It provides:

- `install()` - Install all components
- `repair()` - Fix detected issues
- `uninstall()` - Remove all components
- `inspectSystem()` - Check system state

**Key Principle:** All system modifications go through InstallerEngine. Never call system components directly.

### PermissionOracle

The **PermissionOracle** is the single source of truth for permission state:

- Apple APIs are authoritative (IOHIDCheckAccess)
- TCC database is fallback only
- Caches results for performance

**Key Principle:** Always use PermissionOracle. Never check permissions directly.

### ConfigurationService

The **ConfigurationService** manages the config file:

- Generates Kanata config from UI state
- Preserves user custom sections
- Hot-reloads changes via TCP

**Key Principle:** JSON stores are source of truth. Config file is generated output.

## Configuration Model

KeyPath uses a two-file configuration model:

```
~/.config/keypath/
  keypath-apps.kbd    ← KeyPath owns (regenerated)
  keypath.kbd         ← User owns (preserved)
```

Your `keypath.kbd` includes the generated file:

```lisp
(include keypath-apps.kbd)

;; Your custom configuration
```

## Service Architecture

### LaunchDaemon

KeyPath runs Kanata as a LaunchDaemon for:

- System-level access
- Boot-time operation
- Crash recovery
- Reliable operation

### TCP Communication

KeyPath communicates with Kanata via TCP (port 37001):

- Config validation
- Hot reload
- Layer state queries
- Virtual key control

## Key Design Decisions

### No Config Parsing

KeyPath **never** parses Kanata config files. Instead:

- Uses TCP to query state
- Uses simulator for static analysis
- Lets Kanata validate syntax

**Rationale:** Kanata is the source of truth. Parsing would create drift.

### One-Way Generation

Config file is generated from JSON stores:

- UI state → JSON stores → Config file
- Never syncs back from config to UI
- User edits preserved in config

**Rationale:** Prevents conflicts and data loss.

### State-Driven Wizard

The setup wizard is state-driven:

- Detects system state
- Generates issues from state
- Routes to appropriate pages
- Provides one-click fixes

**Rationale:** Handles 50+ edge cases automatically.

## Testing Strategy

### Test Seams

KeyPath uses test seams for testability:

- `TestEnvironment.isRunningTests` guards
- Mock system components
- Override file paths

### Test Categories

- **Unit tests** - Individual components
- **Integration tests** - Component interactions
- **System tests** - Full system validation

## Further Reading

- [ADR-015: InstallerEngine](/adr/adr-015-installer-engine)
- [ADR-023: No Config Parsing](/adr/adr-023-no-config-parsing)
- [ADR-025: Configuration Management](/adr/adr-025-config-management)
- [ADR-027: App-Specific Keymaps](/adr/adr-027-app-specific-keymaps)
