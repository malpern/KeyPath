# KanataManager Refactoring Plan

## Problem Statement
`KanataManager` has become a "God Class" (2,800+ lines), handling unrelated responsibilities:
- Process Lifecycle (starting/stopping services)
- Configuration Management (CRUD for mappings)
- AI Integration (HTTP calls to Anthropic)
- UI State Management (View Models)
- Diagnostics & Logging

## Goal
Split `KanataManager` into focused, single-responsibility services while maintaining backward compatibility with existing ViewModels.

## Architecture Overview

```mermaid
graph TD
    UI[SwiftUI Views] --> VM[KanataViewModel]
    VM --> KM[KanataManager (Coordinator)]
    
    KM --> CS[ConfigurationService]
    KM --> LC[LifecycleController]
    KM --> AI[ConfigRepairService]
    KM --> DS[DiagnosticsService]
    
    CS --> Disk[File System]
    LC --> IE[InstallerEngine]
    AI --> Claude[Anthropic API]
```

## Phases

### Phase 1: Foundation (Immediate)
*   **Centralize Paths**: Move hardcoded paths (config paths, log paths, binary paths) to `KeyPathConstants` in `KeyPathCore`.
*   **Abstract AI**: Extract `callClaudeAPI` and `repairConfigWithClaude` into a dedicated `ConfigRepairService` protocol and implementation.
*   **Cleanup**: Remove commented-out legacy code to reduce noise.

### Phase 2: Extract Logic (Medium Term)
*   **Extract Configuration State**: Move `ruleCollections`, `customRules`, and `keyMappings` into a dedicated `ConfigurationStateHolder` or enhance `ConfigurationManager` to own this state. `KanataManager` should just observe it.
*   **Extract Lifecycle**: Move `pauseMappings`, `resumeMappings`, and process monitoring to `DaemonController`.

### Phase 3: Final Split (Long Term)
*   **Reduce KanataManager**: `KanataManager` should become a lightweight facade (or be removed entirely) that delegates 100% of work to sub-services.
*   **Reactive State**: Use `Observable` (Swift 5.9+) for simpler state sharing instead of manual `AsyncStream` bridges where possible.

## Detailed Implementation Steps (Phase 1)

1.  **Create `KeyPathConstants.swift`** in `KeyPathCore`.
    *   Define `Config`, `Logs`, `Binaries` structs.
2.  **Create `Services/AI/ConfigRepairService.swift`**.
    *   Protocol `ConfigRepairService`.
    *   Implementation `AnthropicConfigRepairService`.
3.  **Refactor `KanataManager`**.
    *   Inject `ConfigRepairService`.
    *   Replace hardcoded paths with `KeyPathConstants`.
    *   Delete legacy comments.

