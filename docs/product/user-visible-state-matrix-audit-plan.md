# User-Visible State Matrix Audit Plan

**Status:** Initial audit plan; no production changes authorized
**Date:** 2026-07-10
**North star:** Time from first launch to a successfully confirmed first remap

## Scope And Evidence Rules

This audit maps what a person sees and can do. It does not reopen installer
architecture. Directly observed behavior, fixture-backed behavior, and
code-inferred behavior must remain separately labeled.

No audit step may uninstall KeyPath, reset TCC, remove system components, alter
security settings, or recreate a fresh machine state without explicit user
approval.

Curated screenshots belong under
`docs/product/evidence/user-visible-state-matrix/2026-07-10/`. Raw recordings
and temporary captures belong under the worktree's ignored `.tmp/ux-audit/`
directory. The evidence index will record capture date, build commit, machine
state, journey/state, source, and confidence.

## Short Audit Plan

1. Trace launch, wizard routing, canonical installer results, runtime health,
   completion flags, and every visible page/action.
2. Observe the current healthy launch, checking/revalidation, wizard summary,
   runtime status, and non-destructive settings surfaces with Computer Use.
3. Use previews, tests, fixtures, and source tracing for approval, failure,
   repair, uninstall, and first-run states that cannot safely be reproduced.
4. Build `docs/product/user-visible-state-matrix.md` with one row per meaningful
   visible state and links to indexed evidence.
5. Rank friction by impact on time to first remap, abandonment risk, permission
   trust, dead-end risk, and frequency—not visual polish alone.
6. Define the smallest privacy-conscious event contract that can measure the
   funnel. Do not implement it during the audit.
7. Recommend one reviewable UI slice with observable acceptance criteria,
   focused tests, accessibility coverage, and real-app verification.

## Initial Journey Map

This map is an initial code trace. Unless marked otherwise, it is **inferred**
and must be checked against the running app or a fixture before it becomes a
matrix fact.

| Step | Entry or trigger | Current visible surface | Exit condition | Evidence now | Audit question |
| --- | --- | --- | --- | --- | --- |
| Launch | App activation | Branded splash, then either main surface or setup wizard | Startup validation chooses a usable or incomplete path | Code-inferred from `App.swift` | Does the handoff feel responsive and stable? |
| Welcome | First wizard run, helper absent, welcome flag unset | “Welcome to KeyPath,” setup-time expectation, privacy reassurance, Get Started | User selects Get Started; flag persists | Code-inferred from `WizardWelcomeGate` and `WizardWelcomePage` | Is the next permission request adequately previewed? |
| Checking | Wizard setup/refresh | Summary validation/progress presentation | Canonical inspection result is applied | Code-inferred from `InstallationWizardView` and state management | Are long checks explained without visual churn? |
| Overview | Inspection completes | Setup Overview showing incomplete, unverified, or completed items | User chooses a problem row or routing selects the next relevant page | Code-inferred from `WizardSummaryPage` and `WizardSystemStatusOverview` | Is there one obvious next action? |
| Conflict resolution | Conflicting software/process is detected | Resolve System Conflicts with Resolve action | Conflict evidence clears | Code-inferred from router and page | Are consequences and safety clear? |
| Helper setup | Helper missing, stale, unhealthy, or awaiting approval | Privileged Helper page; Enable/Reconnect or Login Items guidance | Functional helper check succeeds or approval remains pending | Code-inferred; functional check exists | Does “privileged helper” expose unnecessary internal vocabulary? |
| Optional diagnostics | Full Disk Access is absent | Enhanced Diagnostics explanation with Enable, Learn more, and Skip | Permission detected or user skips | Code-inferred | Is optionality and privacy cost clear? |
| Accessibility approval | Blocking or unverified permission state | KeyPath and engine status rows with System Settings actions | Permission becomes ready or remains explicitly unverified | Code-inferred | Does the page explain why two entries may appear? |
| Input Monitoring approval | Blocking or unverified permission state | KeyPath and engine status rows with System Settings actions | Permission becomes ready or remains explicitly unverified | Code-inferred | Does KeyPath automatically notice completion reliably? |
| Driver/background approval | VirtualHID/DriverKit or daemon evidence requires attention | Karabiner Driver setup and macOS Drivers/Login Items guidance | Driver/services verify ready, or approval remains pending | Code-inferred | Is “Karabiner” meaningful or alarming to a new user? |
| Runtime startup | Service missing, stopped, or ready | Start Keyboard Service page with status and primary action | Process and TCP readiness become healthy | Code-inferred | Is startup success acknowledged in user language? |
| Communication verification | Runtime is live but TCP/config evidence needs attention | Communication page | TCP/config evidence becomes healthy | Code-inferred | Is this implementation detail avoidable in the normal journey? |
| Setup ready | Active state with no issues | “KeyPath Ready” and Close Setup | User closes setup | Code-inferred | Does “ready” prove a remap works or only system health? |
| First remap | Setup closes into the product | No dedicated prompt/confirmation found in the initial trace | Not defined | **Unknown; absence inferred from search only** | What action should create and confirm the first successful remap? |
| Periodic revalidation | Running app refreshes health | Compact main/overlay health state | Fresh validation settles | Code-inferred from `MainAppStateController` | Can healthy checks occur without repeated Ready churn? |
| Repair | User invokes Fix/Repair | Inline progress/toast, approval, success, inconclusive, or failure result | Fresh final evidence is applied or user receives recovery guidance | Code-inferred from owned-run result handling | Does every failure leave one understandable action? |
| Uninstall | User requests uninstall | Uninstall progress and completion/failure surface | Verified removal or explicit failure | Not yet traced | What remains visible after success and failure? |

## Safe Observation Boundary

Safe to observe now:

- healthy launch and reopen;
- normal checking and periodic revalidation;
- current wizard summary and already-granted permission pages;
- runtime-ready and ordinary restart/update states that occur without changing
  system permissions;
- accessibility tree, keyboard navigation, copy, and reduced-motion behavior;
- fixture and snapshot renderings that do not mutate the machine.

Require fixtures or explicit permission:

- virgin first run and every macOS approval gate in an ungranted state;
- missing/stale helper, DriverKit, VirtualHID, or Login Items registration;
- TCC denial, reset, or inconclusive permission evidence;
- destructive conflict reproduction;
- uninstall success/failure and reinstall;
- terminal repair failures that require removing or corrupting components.

## Proposed Matrix Structure

The full matrix will use one row per visible state with these fields: journey,
trigger, current rendering, evidence, likely user interpretation, primary
action, automatic detection, exit condition, dead-end risk, exact copy,
internal vocabulary, accessibility, motion, desired experience, acceptance
criteria, priority, and confidence.

## Initial Gaps And Open Questions

- The welcome experience and setup-ready state are implemented, but the initial
  trace found no explicit first-remap prompt or behavioral confirmation. This
  must be verified in the running product before ranking it as a gap.
- `WizardTelemetry` is an in-memory ring buffer and does not currently provide
  a durable onboarding funnel. Existing analytics/plugin facilities need a
  privacy and transport review before any event contract is implemented.
- Product input is needed on what counts as a “first remap”: activating a built-in
  example, creating a mapping, or successfully observing an expected output.
- Product input is needed on whether first-remap confirmation should be explicit
  (“press this key now”) or inferred from safe aggregate runtime events.

## Deferred Until Evidence Exists

- visual redesign of the full wizard;
- installer module extraction or autonomous repair;
- a new terminal “unable to verify” state;
- analytics implementation;
- proactive service-update UI;
- destructive first-run recreation;
- any implementation slice chosen before the matrix and evidence index are
  complete.
