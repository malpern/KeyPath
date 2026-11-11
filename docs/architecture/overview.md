---
layout: default
title: Architecture Overview
description: System design and architecture of KeyPath
---

# Architecture Overview

KeyPath is built on a clean, modular architecture that separates concerns and ensures reliability.

## High-Level Architecture

```
KeyPath.app (SwiftUI, unprivileged)
  ├─ InstallerEngine            install, repair, uninstall, system inspection
  ├─ RuntimeCoordinator         runtime and configuration orchestration
  └─ ServiceLifecycleCoordinator
        │ launches and supervises
        ▼
Session runtime worker (a second copy of the app, same user)
  - CGEvent tap and synthetic output
  - Kanata engine through the Rust host bridge
  - engine control socket (Unix-domain, admits only the launching app; ADR-046)
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
- Never reads the TCC database (ADR-044); missing evidence stays unknown
- Caches results for performance

**Key Principle:** Always use PermissionOracle. Never check permissions directly.

### ConfigurationService

The **ConfigurationService** manages the config file:

- Generates Kanata config from UI state
- Preserves user custom sections
- Hot-reloads changes through the engine socket

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

### Session Runtime

KeyPath runs Kanata in a user-session worker with no root daemon or driver:

- Runs only while the user is logged in and KeyPath is running
- Holds the user's input permissions (see `guides/privacy.md`)
- Reports its state to the app in a private report file
- Is supervised by `ServiceLifecycleCoordinator`, not launchd. It restarts after
  session boundaries and some recoverable failures; other failures stop it and
  ask the user to reopen KeyPath

The earlier LaunchDaemon design is retired. See
[ADR-045](../adr/adr-045-retire-privileged-runtime-stack.md).

### Engine Communication

KeyPath talks to Kanata with Kanata's JSON control protocol over a Unix-domain
socket the session worker creates, `e-<worker pid>.sock`, in a 0700 directory
(`~/Library/Application Support/KeyPath/control`, or a per-user temporary
directory when that path is too long). The engine admits only the app that
launched the worker: it checks the peer's uid, PID and PID version on every
connection ([ADR-046](../adr/adr-046-session-engine-control-channel.md)).
There is no TCP port. The app reads the socket path from the worker's report.

- Hot reload
- Layer state queries
- Virtual key control
- Key, layer and tap-hold events

The CLI cannot connect to the engine, so its engine commands are runtime-control
requests the app answers ([cli-runtime-control.md](cli-runtime-control.md)).

## External Integration

KeyPath exposes its state and actions to external tools through multiple transports:

```
                    ┌──────────────────────────────────────┐
                    │         External Consumers           │
                    │  Siri, Shortcuts, Hammerspoon, KM    │
                    └───────┬──────────┬──────────┬────────┘
                            │          │          │
              ┌─────────────┘          │          └───────────────┐
              ▼                        ▼                          ▼
  ┌───────────────────┐  ┌───────────────────────┐  ┌────────────────────┐
  │  App Intents      │  │  Distributed Notifs   │  │  keypath:// URLs   │
  │  (query + action) │  │  (outbound events)    │  │  (inbound actions) │
  │  Siri, Shortcuts  │  │  Hammerspoon, KM      │  │  Terminal, any app │
  └───────────────────┘  └───────────────────────┘  └────────────────────┘
```

| Direction | Transport | Implementation |
|-----------|-----------|----------------|
| **Outbound events** | Distributed Notifications | `DistributedNotificationBridge` |
| **Inbound commands** | `keypath://` URL scheme | `DeepLinkRouter` → `ActionDispatcher` |
| **Query + action** | App Intents | `Intents/` — delegates to existing services |
| **CLI** | `keypath` command | `ConfigFacade`, `SystemFacade` |

See [distributed-notifications.md](distributed-notifications.md), [app-intents.md](../guides/app-intents.md), and [action-uri-system.md](../guides/action-uri-system.md).

## Key Design Decisions

### No Config Parsing

KeyPath **never** parses Kanata config files. Instead:

- Queries state from the engine over its socket
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
