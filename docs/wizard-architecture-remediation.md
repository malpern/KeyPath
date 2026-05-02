# Installation Wizard — Architecture Remediation

**Status:** ✅ Substantially complete (2026-05-02)

## What Was Done

The wizard's 11-type state management layer was simplified to 3 core types:

| Deleted | Lines | Replaced By |
|---------|-------|-------------|
| `WizardNavigationEngine` | 468 | `WizardRouter` (pure function) |
| `IssueGenerator` | 480 | `SystemInspector` (pure function) |
| `WizardStateInterpreter` | 257 | Deleted (no callers) |
| `WizardAutoFixer` | 128 | Direct `InstallerEngine.runSingleAction()` |
| `WizardAutoFixerManager` | 43 | Deleted (wrapper removed) |
| `WizardNavigationHeuristics` | 12 | `WizardRouter.shouldNavigateToSummary()` |
| `SystemContextAdapter` (gutted) | 385→28 | Delegates to `SystemInspector` |
| `WizardStateMachine` (simplified) | 404→195 | Thin `@Observable` state container |

## Current Architecture

See [wizard-architecture.html](architecture/wizard-architecture.html) for the visual reference.

**Three types:**
1. `SystemInspector.inspect(context:)` — pure function: SystemContext → (WizardSystemState, [WizardIssue])
2. `WizardRouter.route(state:issues:...)` — pure function: state + issues → WizardPage
3. `InstallationWizardView` — SwiftUI view with @State, calls InstallerEngine directly for fixes

**42 golden tests** verify behavioral equivalence between old and new implementations.

## Remaining Work

- `WizardAsyncOperationManager` (639 lines) — still used for timeout/progress wrapping of state detection and service start. Most of the file is `WizardError` user-friendly messages which are legitimate. The manager could be replaced with simple `Task` + timeout, but callers are deeply woven and the risk/reward isn't worth it now.
