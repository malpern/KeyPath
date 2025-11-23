# Performance & UX Improvement Plan

This plan outlines actionable improvements to make KeyPath's startup and validation flow faster, more resilient, and more responsive, based on analysis of real-world logs.

## 1. Parallelize System Validation (with Constraints)

**Goal:** Reduce total validation time (currently ~2.2s) by running independent checks concurrently, while respecting dependencies.

### Strategy: Async `TaskGroup` with Dependency Graph
We will move from a purely sequential chain to a dependency-based execution model.

**Current (Sequential ~2.2s):**
`Helper` (1.5s) → `Permissions` (0.2s) → `Components` (0.1s) → `Conflicts` (0.1s) → `Health` (0.3s)

**Proposed (Parallel ~1.6s):**
*   **Group A (Concurrent):**
    *   `Helper Check` (Slow, I/O bound)
    *   `Component Check` (Fast file I/O, independent)
    *   `Conflict Check` (Process listing, independent)
*   **Group B (Dependent on User Interaction):**
    *   `Permission Check` (Requires main thread, potentially blocking user prompts. Keep serial or run independent of UI blocking.)
*   **Group C (Final Assembly):**
    *   `Health Check` (Synthesizes results from above)

### Implementation Plan
1.  **Refactor `SystemValidator.checkSystem()`:**
    *   Use `withTaskGroup` to spawn child tasks for `checkHelper`, `checkComponents`, and `checkConflicts`.
    *   `checkPermissions` runs on the Main Actor (required for Oracle/TCC) but can start immediately alongside the others.
    *   `await` all results.
2.  **Safety Constraint:** Ensure `PermissionOracle` maintains its `@MainActor` isolation to prevent race conditions during prompt queries.
3.  **Dependency Handling:** The "Health Check" step (`isServiceHealthy`) relies on knowing if the Helper is active. This must wait for Group A to finish.

## 2. Smart Dev Mode Awareness

**Goal:** Reduce "false alarm" catastrophic errors for developers running unsigned/ad-hoc builds.

### Strategy: Environment Detection & UI Context
1.  **Detection Logic:**
    *   Create `EnvironmentDetector` service.
    *   Check for `DEBUG` build flag.
    *   Check code signing identity (Ad-Hoc vs. Developer ID).
    *   Check if running from `/Applications` vs. Xcode/DerivedData path.
2.  **UI Indicator:**
    *   If `EnvironmentDetector.isDevMode` is true:
        *   Add a subtle `[DEV]` badge to the Settings title bar or bottom status bar.
        *   Uses a muted color (e.g., secondary label color) to keep it clean and non-intrusive.
3.  **Error Handling:**
    *   Intercept "Signature Mismatch" or "Helper Connection" errors.
    *   If in Dev Mode, append a "Developer Hint" to the error message: *"Dev Mode: Run `./Scripts/build.sh` to sign helper."*
    *   Prevent the "Catastrophic Failure" modal for known signature issues in Dev Mode.

## 3. Resilient XPC Connection Strategy

**Goal:** Eliminate the flash of red "Helper Error" when the Helper process starts 50ms slower than the app.

### Strategy: Retry Policy with Exponential Backoff
1.  **Modify `HelperManager.getConnection()`:**
    *   Wrap the connection logic in a retry loop.
    *   **Policy:** 3 attempts.
    *   **Delays:** 100ms, 200ms, 400ms.
    *   **Total Max Wait:** ~700ms (still faster than user perception of "broken").
2.  **Optimistic State:**
    *   While retrying, report status as `.unknown` or `.connecting` instead of `.unresponsive`.
    *   Only return `.unresponsive` error after all retries fail.

## 4. Consolidated "Ready" Signal (Detailed Plan)

**Goal:** Eliminate UI flicker and provide a solid "System is Active" state transition.

### The Problem
Currently, the UI observes multiple published properties: `kanataRunning`, `helperActive`, `permissionsGranted`. These update at slightly different times (ms apart), causing the UI to potentially flicker:
`Loading` → `Error (Helper not ready)` → `Loading` → `Active`.

### The Solution: `SystemReadinessCoordinator`

1.  **New Component:** Create `SystemReadinessCoordinator` (ObservableObject).
2.  **Inputs:** Observes `SystemContext` from `InstallerEngine` (or `SystemValidator`).
3.  **Logic:**
    *   Defines a strict definition of "Ready":
        `isReady = (helper.isHealthy && permissions.areGranted && daemon.isRunning && kanata.isConnected)`
    *   **Debounce:** Applies a 200ms debounce to state changes. This "swallows" the rapid-fire intermediate states during startup.
4.  **Output:** Publishes a single `public enum SystemState { case booting, ready, degraded(issues: [Issue]), failed(error: Error) }`.
5.  **Migration:**
    *   Update `ContentView` to switch primarily on this single `SystemState` enum.
    *   This simplifies the top-level view logic significantly.

### Implementation Steps for "Ready" Signal
1.  Define `SystemReadiness` types in `Core`.
2.  Implement `SystemReadinessCoordinator` that subscribes to the `SystemValidator` updates.
3.  Add the debounce logic using Combine or Swift Concurrency (`Task.sleep` cancellation pattern).
4.  Wire `ContentView` to use this coordinator instead of raw `KanataManager` state for the main status display.

## 5. Future Considerations (Deferred)

### Contextual "Fix" Actions

**Goal:** Reduce friction in resolving specific errors without rewriting the Wizard.

**Specific Opportunities:**
1.  **Permission Denials (Deep Links):** Add "Open Settings" button directly on error cards.
2.  **Driver Mismatch (Direct Download):** Show "Update Driver" button instead of generic "Fix".
3.  **Helper Not Running (Restart Service):** Scope "Fix" to just restarting the helper if that's the only issue.


