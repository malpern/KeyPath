# KeyPath Manager Classes - Responsibility Inventory

**Created:** August 26, 2025  
**Purpose:** Document current manager class responsibilities and boundaries for architectural refactoring  
**Status:** Complete Analysis  

## Overview

KeyPath currently has **8 core manager classes** totaling **6,610 lines** with significant responsibility overlap and unclear boundaries. This document provides a detailed inventory to guide the refactoring plan.

## Core Manager Classes

### 1. KanataManager (3,777 lines) 🚨 CRITICAL
**Location:** `Sources/KeyPath/Managers/KanataManager.swift`  
**Type:** Monolithic orchestrator  
**Threading:** MainActor  

**Primary Responsibilities:**
- **Lifecycle Management**: Start/stop Kanata processes
- **Configuration Management**: Load, validate, watch config files
- **Event Processing**: CGEvent tap handling and key mapping
- **Output Synthesis**: Posting transformed keyboard events
- **TCP Server Management**: Optional network interface
- **Error Handling**: Global error state and recovery
- **UI State Management**: Published properties for SwiftUI
- **Process Monitoring**: Health checks and restart logic
- **Diagnostic System**: Issue detection and auto-repair
- **File Watching**: Config file change monitoring

**Owned Resources:**
- CGEvent taps (keyboard and mouse)
- File system watchers
- Background timers for health checks
- TCP server socket (optional)
- Kanata subprocess

**Dependencies:**
- ApplicationServices (CGEvent)
- Network (TCP server)
- IOKit (HID system)
- Foundation (file operations)

**Key Issues:**
- Violates single responsibility principle massively
- Contains 10+ distinct concerns in one class
- Impossible to test individual components
- Single point of failure for entire application

### 2. SimpleKanataManager (712 lines) ⚠️ HIGH
**Location:** `Sources/KeyPath/Managers/SimpleKanataManager.swift`  
**Type:** Simplified lifecycle coordinator  
**Threading:** MainActor  

**Primary Responsibilities:**
- **Simple State Management**: 4-state model (starting, running, needsHelp, stopped)
- **Auto-start Logic**: Automatic Kanata startup attempts
- **User-Friendly Error Handling**: Simplified error reporting
- **Wizard Integration**: Triggers installation wizard when needed
- **Health Monitoring**: Basic process health checks
- **Retry Logic**: Auto-retry with backoff

**Owned Resources:**
- State timers
- Health check timers
- Auto-start attempt tracking

**Dependencies:**
- KanataManager (delegation)
- SwiftUI (Published properties)

**Key Issues:**
- **Overlaps with KanataManager lifecycle logic**
- **Duplicates health monitoring functionality**
- Unclear when to use vs KanataLifecycleManager

### 3. KanataConfigManager (533 lines) 📋 MEDIUM
**Location:** `Sources/KeyPath/Managers/KanataConfigManager.swift`  
**Type:** Configuration handler  
**Threading:** Mixed (serial queue for IO)  

**Primary Responsibilities:**
- **Config File Operations**: Read/write Kanata config files
- **Validation Logic**: Config syntax and semantic validation
- **Template Generation**: Default config creation
- **Backup Management**: Config file backup and restore
- **Error Recovery**: Config corruption detection and repair

**Owned Resources:**
- Serial dispatch queue for file operations
- Config file locks
- Backup file tracking

**Dependencies:**
- Foundation (file operations)
- Regular expressions for validation

**Key Issues:**
- Should be extracted from manager proliferation
- Good candidate for service extraction
- Clear, focused responsibilities

### 4. KanataLifecycleManager (426 lines) 🔄 MEDIUM  
**Location:** `Sources/KeyPath/Managers/KanataLifecycleManager.swift`  
**Type:** State-driven lifecycle coordinator  
**Threading:** MainActor  

**Primary Responsibilities:**
- **State Machine Integration**: Uses LifecycleStateMachine (381 lines)
- **UI Bridge**: Connects state machine to SwiftUI
- **Auto-start Coordination**: Manages automatic startup flow
- **Wizard Triggering**: Determines when to show installation wizard
- **State Publishing**: Publishes state changes to UI

**Owned Resources:**
- LifecycleStateMachine instance
- State change publishers

**Dependencies:**
- KanataManager (process operations)
- LifecycleStateMachine
- SwiftUI (Observable)

**Key Issues:**
- **Direct overlap with SimpleKanataManager**
- **Both handle auto-start logic differently**
- Unclear choice criteria between the two

### 5. LifecycleStateMachine (381 lines) 🤖 MEDIUM
**Location:** `Sources/KeyPath/Managers/LifecycleStateMachine.swift`  
**Type:** State transition coordinator  
**Threading:** MainActor  

**Primary Responsibilities:**
- **State Transitions**: 14-state finite state machine
- **Operation Sequencing**: Coordinates complex startup/shutdown flows
- **Error State Management**: Handles transition failures
- **State Validation**: Ensures valid state transitions

**Owned Resources:**
- State transition timers
- Operation queues
- State history tracking

**Dependencies:**
- Foundation (timers, async operations)

**Key Issues:**
- Complex 14-state model vs SimpleKanataManager's 4-state model
- Unclear which state model is authoritative
- Could be shared by both lifecycle managers

### 6. ProcessLifecycleManager (341 lines) ⚙️ LOW
**Location:** `Sources/KeyPath/Managers/ProcessLifecycleManager.swift`  
**Type:** Process ownership coordinator  
**Threading:** MainActor  

**Primary Responsibilities:**
- **PID File Management**: Deterministic process ownership tracking
- **Intent-Based Reconciliation**: Desired vs actual process state
- **Process Conflict Resolution**: Handles multiple Kanata instances
- **Resource Cleanup**: Ensures clean process termination

**Owned Resources:**
- PID files
- Process monitoring

**Dependencies:**
- Foundation (process operations)
- System (process APIs)

**Key Issues:**
- Well-focused responsibilities
- Good abstraction over process management
- Minimal overlap with other managers

### 7. LaunchAgentManager (262 lines) 🚀 LOW
**Location:** `Sources/KeyPath/Managers/LaunchAgentManager.swift`  
**Type:** launchctl integration  
**Threading:** Background queues  

**Primary Responsibilities:**
- **LaunchDaemon Operations**: Install/uninstall system services
- **Service Status Checking**: Query launchctl service state
- **Plist Generation**: Create proper LaunchDaemon plists
- **Privilege Escalation**: Handle sudo operations

**Owned Resources:**
- launchctl subprocess operations
- Temporary plist files

**Dependencies:**
- Foundation (process operations)
- System (launchctl)

**Key Issues:**
- Clear, focused responsibilities
- Good encapsulation of system integration
- No significant overlap with other managers

### 8. LaunchDaemonPIDCache (178 lines) 💾 LOW
**Location:** `Sources/KeyPath/Managers/LaunchDaemonPIDCache.swift`  
**Type:** PID tracking utility  
**Threading:** Thread-safe  

**Primary Responsibilities:**
- **PID Caching**: Cache process IDs for performance
- **Cache Invalidation**: Manage cache lifecycle
- **Process Lookup**: Fast process existence checks

**Owned Resources:**
- In-memory PID cache
- Cache timers

**Dependencies:**
- Foundation (collections, timers)

**Key Issues:**
- Very focused utility class
- No architectural concerns
- Could remain as-is or be absorbed into ProcessLifecycleManager

## Additional Manager-like Classes (Outside Core Managers/)

### WizardStateManager (InstallationWizard/UI/)
**Responsibilities:** Installation wizard state coordination  
**Issues:** UI-coupled, should remain separate from core managers

### PackageManager (InstallationWizard/Core/)  
**Responsibilities:** Package installation operations  
**Issues:** Well-scoped, installer-specific

### VHIDDeviceManager (InstallationWizard/Core/)
**Responsibilities:** Virtual HID device management  
**Issues:** Hardware-specific, appropriate scope

## Responsibility Overlap Analysis

### Critical Overlaps

1. **Lifecycle Management**
   - KanataManager: Direct process operations
   - SimpleKanataManager: 4-state lifecycle
   - KanataLifecycleManager: 14-state lifecycle via state machine
   - **Impact:** Inconsistent behavior, multiple sources of truth

2. **Auto-start Logic**  
   - SimpleKanataManager: Simple retry with backoff
   - KanataLifecycleManager: Complex state-driven startup
   - **Impact:** Duplicate code paths, unclear precedence

3. **Health Monitoring**
   - KanataManager: TCP health checks, process monitoring
   - SimpleKanataManager: Basic health checks
   - **Impact:** Multiple monitoring systems, resource waste

4. **Error Handling**
   - KanataManager: Global error state
   - SimpleKanataManager: User-friendly error messages
   - **Impact:** Inconsistent error experience

### Clear Boundaries (Good Examples)

1. **KanataConfigManager**
   - Focused on configuration file operations
   - Clear input/output contracts
   - Minimal dependencies

2. **LaunchAgentManager**
   - System integration only
   - No business logic overlap
   - Well-defined scope

3. **ProcessLifecycleManager** 
   - Process ownership and PID management
   - Intent-based design pattern
   - Clean separation of concerns

## Threading and Resource Model

### MainActor Classes
- KanataManager (UI state)
- SimpleKanataManager (UI state)  
- KanataLifecycleManager (UI state)
- LifecycleStateMachine (state transitions)
- ProcessLifecycleManager (coordination)

### Background Processing
- KanataConfigManager (file I/O on serial queue)
- LaunchAgentManager (subprocess operations)

### Resource Ownership Conflicts
- **CGEvent Taps**: KanataManager owns multiple taps
- **File Watchers**: KanataManager owns config watchers
- **Process Monitoring**: Multiple classes check process status
- **State Publishers**: Multiple @Published properties for similar state

## Recommendations for Refactoring

### Phase 1: Address Critical Issues
1. **Split KanataManager** using extensions (Milestone 1)
2. **Extract ConfigurationService** from KanataManager (clear boundaries)
3. **Consolidate lifecycle logic** via LifecycleOrchestrator

### Phase 2: Eliminate Overlaps  
1. **Choose single lifecycle approach** (SimpleKanataManager's 4-state model recommended)
2. **Unify auto-start logic** in LifecycleOrchestrator
3. **Single health monitoring system** via centralized service

### Phase 3: Service Extraction
1. **Extract MappingEngine** from KanataManager
2. **Extract EventProcessor** from KanataManager  
3. **Extract OutputSynthesizer** from KanataManager

### Preserve as Focused Services
- KanataConfigManager → ConfigurationService
- LaunchAgentManager (keep as-is)  
- ProcessLifecycleManager (keep as-is)
- LaunchDaemonPIDCache (absorb into ProcessLifecycleManager)

## Composition Root Location

Current manager construction appears to happen in:
- `ContentView.swift` or similar SwiftUI entry point
- App delegate or bootstrap code
- Individual manager initializers

**Recommendation:** Create centralized `CompositionRoot.swift` for dependency injection and service wiring.

## Next Steps

1. **Validate CGEvent tap usage** for EventTag compatibility
2. **Identify all @Published property dependencies** between managers  
3. **Map current initialization flow** to preserve construction order
4. **Create test coverage** for critical manager interactions before refactoring

---

This inventory provides the foundation for systematic architectural refactoring while preserving KeyPath's stability and functionality.