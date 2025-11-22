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
│  │ PermissionOracle│  │    KanataManager   │  │    InstallerEngine   │  │
│  │ (Truth Source)  │  │ (Service Control)  │  │   (Setup Façade)     │  │
│  └─────────────────┘  └────────────────────┘  └──────────────────────┘  │
└───────────┬──────────────────┬────────────────────────┬─────────────────┘
            │                  │                        │
            ▼                  ▼                        ▼
┌─────────────────────────┐ ┌──────────────────────┐ ┌────────────────────┐
│   com.keypath.kanata    │ │   VirtualHID Driver  │ │    MacOS TCC API   │
│   (Root LaunchDaemon)   │ │    (Kernel Ext)      │ │ (Security Frame)   │
└─────────────────────────┘ └──────────────────────┘ └────────────────────┘
```

## Core Architectural Principles

### 1. PermissionOracle: Single Source of Truth
KeyPath uses a dedicated Actor, `PermissionOracle`, to manage the complex state of macOS permissions.
*   **Apple APIs First**: We trust `IOHIDCheckAccess` from the GUI context as the authoritative source.
*   **TCC Fallback**: We query the TCC database only when Apple APIs return "Unknown", typically during initial setup chicken-and-egg scenarios.
*   **Caching**: Results are cached for ~1.5s to balance UI responsiveness with system load.
*   **Principle**: Never bypass the Oracle. If the Oracle says permission is denied, the UI must reflect that, even if other heuristics suggest otherwise.

### 2. InstallerEngine: The Setup Façade
The `InstallerEngine` provides a unified, declarative API for all installation, repair, and uninstall operations.
*   **Declarative API**: `run(intent: .install)` handles everything.
*   **State-Driven Planning**: `inspectSystem()` -> `makePlan()` -> `execute()`.
*   **Recipe-Based Execution**: Atomic `ServiceRecipe` units ensure consistent operations.
*   **Unified Reporting**: Returns structured `InstallerReport` for UI and logging.
*   **Supersedes**: Replaces ad-hoc logic in `WizardAutoFixer` and direct manager calls.

### 3. State-Driven Installation Wizard
The installation wizard is not a linear script but a state machine.
*   **Pure Function Detection**: `SystemStatusChecker` examines the system state (permissions, drivers, processes) without side effects.
*   **Deterministic Navigation**: `WizardNavigationEngine` maps the detected state + current issues to the exact page the user needs to see.
*   **Auto-Fixer**: Atomic, idempotent actions (e.g., `restartVirtualHIDDaemon`) resolve specific issues without brittle scripting.

### 4. Service Architecture (LaunchDaemons)
KeyPath relies on system-level persistence via `launchd`.
*   **Kanata Service**: `com.keypath.kanata` runs the `kanata` binary as root.
*   **VirtualHID Services**: Separate services manage the kernel driver connection.
*   **Why Split?**: Allows granular health checks. If the driver crashes, we can restart just the driver service without killing the main app or the remapping engine.

### 5. Process Lifecycle Management
We use a `PID file` strategy to track ownership of the `kanata` process.
*   **Ownership**: We write a PID file when we start `kanata`.
*   **Conflict Detection**: We check for running `kanata` processes that *don't* match our PID. These are flagged as "external conflicts" (e.g., a user running `kanata` in a terminal).
*   **Recovery**: On startup, we check for orphaned PID files or processes and clean them up.

## Critical Implementation Details

### Permission Checking
We check permissions from the **GUI context** (User Session), not the Root Daemon context.
*   **Reason**: macOS `root` processes often cannot self-report TCC status accurately due to "responsible process" inheritance rules.
*   **Pattern**: The UI checks if it *could* listen to keystrokes. If yes, we assume the root daemon (which has even more power) can too, provided it is launched correctly.

### Inter-Process Communication (IPC)
Communication between the UI and the Root Daemon happens via **TCP**.
*   **Protocol**: Lightweight JSON payloads over TCP port 37001.
*   **Performance**: < 100ms latency for status updates.
*   **Usage**: Sending config reloads, receiving "heartbeat" status updates.
*   **Security**: Localhost-only binding.

## Project Structure

*   `Sources/KeyPathAppKit`: The monolithic library containing most UI and Logic.
*   `Sources/KeyPathHelper`: The privileged helper tool for admin tasks.
*   `Sources/KeyPathPermissions`: The Oracle and permission logic.
*   `Sources/KeyPathDaemonLifecycle`: Service management and PID logic.
*   `Scripts/`: Build, test, and maintenance scripts.

## Development Guidelines

1.  **Logging**: Use `AppLogger`. Start logs with emojis for readability (🚀 start, ✅ success, ❌ error).
2.  **Concurrency**: Use Swift 6 concurrency (`async`/`await`, `Actor`). Avoid completion handlers.
3.  **Tests**: Run `./test.sh` before committing. Do not use `sudo` in tests; mock the system environment.
