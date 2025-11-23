# KanataManager Refactoring Plan

This document outlines the step-by-step plan to decompose the `KanataManager` monolith into maintainable, single-responsibility services. The goal is to improve clarity, testability, and flexibility without over-engineering.

## Phase 1: Cleanup & Centralization
**Goal:** Reduce visual noise and eliminate "magic strings" to make the actual logic visible.

### 1. Legacy Code Excision
*   **Action:** Aggressively delete all code blocks labeled `// Legacy removed`, `// Removed:`, or `// Deprecated` in `KanataManager.swift` and its extensions.
*   **Why:** These comments add massive cognitive load and hide the active logic. Git history is the backup.

### 2. Centralize System Paths
*   **Action:** Create `SystemConstants.swift` in `KeyPathCore`.
*   **Content:** Define static constants for all hardcoded paths:
    *   Config directory: `~/.config/keypath`
    *   Config filename: `keypath.kbd`
    *   Log paths: `/var/log/com.keypath.kanata.stderr.log`
    *   Daemon support paths: `/Library/Application Support/...`
    *   TCC database paths.
*   **Implementation:** Replace all string literals in `KanataManager`, `InstallerEngine`, and `KanataManager+Configuration`.

---

## Phase 2: AI & Configuration Abstraction
**Goal:** Decouple "Intelligence" from "Runtime Management" and make models swappable.

### 3. Extract AI Service Layer
*   **Action:** Define protocol `AIConfigRepairService`.
    *   **Input:** `(brokenConfig: String, errors: [String], intendedMappings: [KeyMapping])`
    *   **Output:** `String` (Fixed Config)
*   **Implementation:**
    *   Create `AnthropicRepairService` implementing this protocol (move logic from `KanataManager.callClaudeAPI`).
    *   Allows future addition of `OllamaRepairService` or `OpenAIRepairService`.
*   **Integration:** Inject into `ConfigurationService`. `KanataManager` delegates repair requests to `ConfigurationService`, which calls the AI.

### 4. Consolidate Configuration Logic
*   **Action:** Move all "file manipulation" logic out of `KanataManager`.
*   **Move:**
    *   `backupCurrentConfig`
    *   `restoreLastGoodConfig`
    *   `saveGeneratedConfiguration`
    *   `handleInvalidStartupConfig`
*   **Destination:** `ConfigurationService` (or new `ConfigLifecycleManager`).
*   **Result:** `KanataManager` becomes a coordinator that requests saves but doesn't handle file I/O.

---

## Phase 3: UI State Separation (MVVM Cleanup)
**Goal:** Stop `KanataManager` from managing View state.

### 5. Extract UI Notification State
*   **Action:** Identify UI-only properties in `KanataManager`:
    *   `showingValidationAlert`
    *   `validationAlertTitle`
    *   `saveStatus`
    *   Direct `SoundManager` calls
*   **Refactor:** Move this state into `KanataViewModel` or a dedicated `AppState` observable.
*   **Pattern:** `KanataManager` emits events (e.g., `.validationFailed(error)`). The `ViewModel` listens and decides to show an alert or play a sound.

---

## Phase 4: The Final Split (Service Architecture)
**Goal:** `KanataManager` becomes a thin coordinator.

### 6. Split into Functional Services
Decompose the remaining logic into injected services:
*   **`ProcessCoordinator`**: Handles start/stop/restart logic (delegating to `InstallerEngine`).
*   **`HealthMonitor`**: Ensure it owns *all* health logic.
*   **`DiagnosticService`**: Ensure it owns *all* log parsing (remove `analyzeLogContent` from Manager).

### 7. Rename to `RuntimeCoordinator`
*   **Action:** Rename `KanataManager` to `RuntimeCoordinator`.
*   **Responsibility:** It simply listens to events from the services above and updates the UI stream. It does *not* do the work itself.

## Proposed Architecture Diagram

```mermaid
graph TD
    UI[SwiftUI Views] --> ViewModel[KanataViewModel]
    
    ViewModel --> Coordinator[RuntimeCoordinator (old KanataManager)]
    
    Coordinator --> ConfigService[ConfigurationService]
    Coordinator --> ProcessService[InstallerEngine / ProcessCoordinator]
    Coordinator --> AIService[<<AIConfigRepairService>>]
    
    ConfigService --> Constants[SystemConstants]
    ProcessService --> Constants
    
    AIService -.-> Anthropic[AnthropicProvider]
    AIService -.-> Ollama[OllamaProvider]
```
