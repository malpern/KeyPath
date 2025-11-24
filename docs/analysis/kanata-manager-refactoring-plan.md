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

> **Progress (Nov 24, 2025):** Health/TCP monitoring has been consolidated inside `KanataService`, and `RuntimeCoordinator` now consumes the façade instead of talking to `ServiceHealthMonitor` directly. The wizard’s Kanata Service page (start/stop/restart/status), the Karabiner Components “post-fix” restart, the async “Start Service” operation, the nuclear “Reset Everything” flow, the fast-path branch of `restartUnhealthyServices()`, the LaunchDaemon install auto-fix, the Fix button’s restart/auto-fix chain, the CLI `keypath-cli repair` command (fast façade restart before `InstallerEngine`), the in-app Emergency Stop, `RuntimeCoordinator.restartServiceWithFallback`, the Settings Status tab (start/stop/status refresh, rules gating), the uninstall dialog, the wizard’s bulk Fix button fallback, the wizard state detector, and the SimpleMods service now all go through `RuntimeCoordinator`/`KanataService`. Remaining work is to route the few helper-only entry points (legacy helper UI, Settings toggle) that still invoke `InstallerEngine` directly.

> **Remaining Direct Callers (Nov 24, 2025):**
>
> 1. **Legacy helper documentation:** Helper onboarding notes and archived planning docs still instruct new devs to instantiate `InstallerEngine` directly. Update them to describe the façade-first approach (RuntimeCoordinator/KanataService/ProcessCoordinator).

### 6. Split into Functional Services
Decompose the remaining logic into injected services:
- [ ] **`ProcessCoordinator`**: Handles start/stop/restart logic (delegating to `InstallerEngine`). _Status:_ `ProcessCoordinator` now wraps `KanataService` for start/stop/restart (with installer fallback). Wizard flows (Kanata Service page, Components page post-fix, async Start button, Reset Everything, restartUnhealthyServices fast-path, LaunchDaemon install auto-fix, and the Fix button’s fast-path restart + auto-fix chain) now reuse the façade. Remaining direct callers: wizard repair recipes that still call `InstallerEngine.run(intent: .repair, using:)` for bulk fixes and helper-specific tools (e.g., CLI repair, legacy helper UI) that spin up their own `PrivilegeBroker`. Next step is to route those repair recipes through façade helpers (start/stop/status) before invoking InstallerEngine for heavy installs.
- [x] **`HealthMonitor`**: Ensure it owns *all* health logic. _Status:_ `KanataService` now owns `ServiceHealthMonitor`, and callers (RuntimeCoordinator, DiagnosticsManager, TCP reloads) invoke façade helpers instead of keeping their own monitors.
- [x] **`DiagnosticService`**: Ensure it owns *all* log parsing (remove `analyzeLogContent` from Manager). _Status:_ `DiagnosticsService` now performs log parsing and real-time VirtualHID monitoring; RuntimeCoordinator simply forwards events.

### 7. Rename to `RuntimeCoordinator`
- [x] **Action:** Rename `KanataManager` to `RuntimeCoordinator`.
- [x] **Responsibility:** It simply listens to events from the services above and updates the UI stream. (UI state now flows through `KanataViewModel`; remaining service wiring is being migrated.)

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
