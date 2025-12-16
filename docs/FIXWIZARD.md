# Fix Wizard Reliability Plan

This document describes the remaining Block 2 work for the installation wizard.
Block 2 focuses on wizard UX,
fix orchestration,
and correctness of status indicators,
without changing the working Kanata / permissions architecture.

Status:
Done as of 2025-12-16.

## Goals

- Make Fix flows reliable.
  No silent no-ops,
  no infinite “Preparing…” loops,
  and no “all green” states when the system is not actually healthy.
- Make progress visible and local.
  When a fix is blocked by another fix,
  the UI explains what is happening,
  shows progress,
  and eventually returns to an actionable state.
- Keep the current working model.
  Do not regress real key capture,
  and keep the `1 → 2` mapping working.

## Non-Goals

- Do not change how Kanata is launched,
  the daemon model,
  or how permissions are granted and checked.
- Do not bump Karabiner / VirtualHID versions as part of this work.
- Do not reintroduce prior experimental permission-gating approaches.

## Hard Constraints

- Preserve the “working permissions/launch model”
  that restored reliable keyboard capture and `1 → 2` mapping behavior.
- All system modification must go through `InstallerEngine`,
  per `AGENTS.md`.
- Permissions checks must go through `PermissionOracle.shared`,
  per `AGENTS.md`.
- Prose and docs use semantic line breaks (SemBr),
  per `AGENTS.md`.

## Current State (What’s Already Landed)

These are the Block 2 items already merged to `master`,
and should be preserved while iterating.

- Wizard Helper page login-items UX,
  including an in-app screenshot and diagnostic logging.
  - `Sources/KeyPathAppKit/InstallationWizard/UI/Pages/WizardHelperPage.swift`
  - `Sources/KeyPathApp/Resources/permissions-login-items.png`
- Wizard Karabiner page unblocking when Karabiner becomes healthy,
  plus readiness transition logs.
  - `Sources/KeyPathAppKit/InstallationWizard/UI/Pages/WizardKarabinerComponentsPage.swift`
- Settings → Status navigation into wizard pages,
  using `sheet(item:)` to avoid SwiftUI sheet caching issues.
  - `Sources/KeyPathAppKit/UI/SettingsView.swift`
  - `Sources/KeyPathWizardCore/WizardTypes.swift`

## Remaining Block 2 Features

This section is preserved for historical context.
The items below are implemented,
and this document now serves as a record of the approach and constraints.

### 1) Inline progress UI (per design request)

- Replace any “separate bar” progress UI
  with a small inline bar styled like the “Preparing…” label treatment.
- No countdown timer text.
- Remove a spinner next to “Preparing…”,
  but keep the spinner on the Fix button while the action is running.

### 2) Fix single-flight that doesn’t deadlock

- Clicking Fix while another fix is running should not be a dead-end toast.
- The UI should show:
  - which fix is currently running,
  - which fix is blocked,
  - and what to do next if user action is required.

### 3) Stuck fix detection and recovery

- If an operation exceeds its deadline,
  mark it as timed out,
  release UI loading states,
  and clear “in flight” locks.
- Expose actionable messaging,
  including a link to diagnostics and logs.

### 4) Dependency-aware messaging

- If a fix cannot start because a prerequisite is unmet,
  show that inline and route the user to the prerequisite step.
- Examples:
  Login Items approval pending,
  driver extension disabled,
  services unhealthy.

### 5) Status correctness and aggregation

- A page’s header icon should not show green
  unless all sub-requirements for that page are satisfied.
- Status should be consistent between:
  wizard pages,
  wizard summary,
  and Settings → Status.

### 6) Spacing/padding consistency

- Bring remaining outlier pages/components
  in line with `WizardDesign.Spacing`.

## Implementation Plan

### Phase 0: Guardrails and safety checks

1. Add a short “do not touch” checklist to PR descriptions for this work:
   - No Kanata launch architecture changes.
   - No driver version bumps.
   - No permission-check rewrites.
2. Add a “smoke checklist” step to every iteration:
   - Run wizard to completion.
   - Confirm `1 → 2` mapping works.

### Phase 1: Single source of truth for fix runtime state

Problem:
Fix state is spread across multiple booleans and managers.
This can lead to “Fix already running…” with no visible progress,
or stuck spinners when a fix completes but UI doesn’t update.

Approach:
Introduce a small view-model style state object,
owned by the wizard view layer,
that describes what fix is running and why.

Deliverables:
- `WizardFixRuntimeState` (new type),
  containing:
  - `currentAction: AutoFixAction?`
  - `blockedBy: AutoFixAction?`
  - `startedAt: Date?`
  - `deadline: Date?`
  - `progress: Double?` (nil = indeterminate)
  - `phaseText: String?` (“Preparing…”, “Restarting…”, etc.)
  - `lastError: String?`
- A single “begin fix” method that enforces single-flight
  and sets `WizardFixRuntimeState` consistently.

Primary touchpoints:
- `Sources/KeyPathAppKit/InstallationWizard/UI/InstallationWizardView.swift`
- `Sources/KeyPathAppKit/InstallationWizard/Core/WizardAsyncOperationManager.swift`

### Phase 2: Inline progress bar component (small, in-place)

Problem:
Users need “local” progress near the action they took.
The progress UI should not add a separate overlay bar,
and should match existing wizard spacing.

Approach:
Add a tiny inline progress bar component,
and standardize how pages display it.

Deliverables:
- `InlineWizardProgressBar` (new SwiftUI view),
  visually:
  - small width,
  - centered,
  - no countdown text,
  - no extra panel background.
- Replace “Preparing…” spinner-with-text patterns
  with:
  - the label,
  - the inline bar,
  - and the button spinner.

Primary touchpoints:
- `Sources/KeyPathAppKit/InstallationWizard/UI/Components/WizardProgressIndicator.swift`
  (either extend,
  or add a sibling component)
- Affected wizard pages that show “Preparing…” states.

### Phase 3: Fix “already running” UX (blocked state)

Problem:
Toasts like “Fix already running…” are easy to miss
and don’t explain what to do.

Approach:
When a fix is blocked,
render an inline status just under the hero,
including:
“Completing <X> before starting <Y>…”
plus the inline progress bar.

Deliverables:
- Replace toast-only guards with:
  - inline status presentation,
  - disable Fix button,
  - optional “View diagnostics” action.

Primary touchpoints:
- `Sources/KeyPathAppKit/InstallationWizard/UI/InstallationWizardView.swift`
  (global Fix entrypoint)
- Per-page fix handlers,
  for example:
  `Sources/KeyPathAppKit/InstallationWizard/UI/Pages/WizardKarabinerComponentsPage.swift`

### Phase 4: Deterministic timeouts and recovery

Problem:
Some fixes can hang due to system prompts,
driver load timing,
or background services state.
The UI must recover rather than looping forever.

Approach:
Centralize timeouts and define “timeout behavior”:
on timeout,
clear operation state and surface an inline error.

Deliverables:
- Add deadlines per action,
  using existing per-action timeout logic as input.
- On timeout:
  - call `resetStuckOperations()` on `WizardAsyncOperationManager`,
  - clear wizard fix locks,
  - show inline error messaging,
  - keep Fix available to retry.

Primary touchpoints:
- `Sources/KeyPathAppKit/InstallationWizard/Core/WizardAsyncOperationManager.swift`
- `Sources/KeyPathAppKit/InstallationWizard/UI/InstallationWizardView.swift`

### Phase 5: Status aggregation correctness (no false greens)

Problem:
It’s possible for a parent page to appear green
while a subtask is still failing,
which is confusing
and hides required action.

Approach:
Treat each wizard page as “green iff all required items are satisfied”.
Formalize this by:
mapping issues to pages
and computing per-page status with tests.

Deliverables:
- Audit and adjust:
  `getRelevantIssues(for:in:)`
  and related evaluators.
  - `Sources/KeyPathAppKit/InstallationWizard/Core/WizardStateInterpreter.swift`
- Add tests to lock behavior.
  The test suite should cover:
  - background services failing ⇒ Karabiner page not green,
  - missing Kanata input monitoring ⇒ Input Monitoring page not green,
  - summary rollups agree with Settings → Status.

### Phase 6: Dependency messaging

Approach:
For the top failure modes we have observed,
add explicit inline help with one-click navigation:

- Login Items approval required ⇒ open System Settings Login Items.
- Driver extension disabled ⇒ open Privacy & Security extensions page.
- Input Monitoring / Accessibility ⇒ open the relevant Privacy page,
  with instructions for selecting the correct binary entry.

Deliverables:
- Short, accurate “what to do” text on each affected page.
- Links and buttons that open the correct System Settings pane.

### Phase 7: Layout/padding consistency

Approach:
Use `WizardDesign.Spacing` and existing page containers consistently.
Avoid one-off paddings.

Deliverables:
- Audit pages for inconsistencies,
  and align them to the standard patterns.

## Validation Checklist (Every Iteration)

- Wizard completes without getting stuck.
- Fix button never becomes a permanent spinner state.
- Timeout path triggers and recovers if a fix runs too long.
- Settings → Status rows open wizard to the correct page.
- Page icons only show green when all sub-requirements are satisfied.
- `1 → 2` mapping works after setup,
  confirming real key capture is still functional.

## Notes

The wizard already contains some infrastructure that can be built upon:
- Single-flight guards and “already running” toasts exist today,
  but should be surfaced inline for clarity.
  - `Sources/KeyPathAppKit/InstallationWizard/UI/InstallationWizardView.swift`
- `WizardAsyncOperationManager` already tracks running operations and progress,
  and includes `resetStuckOperations()`.
  - `Sources/KeyPathAppKit/InstallationWizard/Core/WizardAsyncOperationManager.swift`

The plan above focuses on making that infrastructure user-visible,
deterministic,
and resistant to system timing edge cases.
