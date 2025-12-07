# Installation Wizard – Architectural Challenges and Remediation Plan

## Snapshot (Nov 26, 2025)
- Dual control stacks: the new `WizardStateMachine` exists, but the UI still runs through `WizardStateManager + WizardNavigationEngine + WizardNavigationCoordinator`, so navigation and refresh behavior are duplicated and can diverge.
- Timing-based coordination: sleeps/delays (50–100 ms, 60 s polling) gate navigation and validation, making outcomes sensitive to scheduler timing rather than system state.
- Façade bypasses: auto-fix paths call helper/driver/service routines directly instead of using `InstallerEngine.run(intent:using:)`, so “Fix” vs “Install/Repair” can produce different side effects and idempotence.
- Non-deterministic navigation inputs: `navSequence` is built from UI state, not a pure function of the latest snapshot, so routing can differ for the same underlying state.
- Blocking/system calls on main actor: `SystemValidator` still shells out to `pgrep` on the main actor for Karabiner, risking UI stalls and flakiness.
- Progress simulated with fixed sleeps (InstallerEngine driver activation, wizard auto-fix), which can under- or overshoot real readiness.

## Remediation Plan (sequenced)
1) **Unify control stack**
   - Make `InstallationWizardView` consume `WizardStateMachine` for state + navigation; remove `WizardStateManager`, `WizardNavigationEngine/Coordinator` after parity tests.
   - Expose a single observable snapshot (SystemSnapshot) and derived page via pure function; no UI-managed `navSequence`.

2) **Deterministic routing**
   - Define one pure routing function: `page = route(snapshot)`; keep it side-effect free and sync with tests.
   - Drive summary lists from the same function so displayed issues match navigation.

3) **Façade-only fixes**
   - Wire all auto-fix buttons to `InstallerEngine.run(intent:, using:)` (or a single-action helper that still builds an InstallPlan). Remove direct helper/driver/service calls from `WizardAutoFixer`.
   - Keep policy: system modifications go through `InstallerEngine`; runtime checks through `PermissionOracle.shared`.

4) **Replace timing sleeps with readiness checks**
   - Swap fixed delays for polling on concrete signals (ServiceHealthChecker for launchd services, VHIDDeviceManager for driver activation, helper health for Login Items approval).
   - Remove UI “wait 50 ms” and “sleep 60 s” guards; use debounced async tasks keyed by snapshot version.

5) **Move process checks off main actor**
   - Replace `pgrep` shell-out with `ProcessLifecycleManager` / `ServiceHealthChecker` and ensure it runs off the main actor; keep results cached per validation run.

6) **Idempotence + test coverage**
   - Add snapshot-based golden tests: identical snapshots must yield the same page and same plan/recipes.
   - Add regression tests that “Fix” and “Install/Repair” execute identical `InstallerEngine` recipes for the same missing/failed components.
   - Add async determinism tests (no sleeps) around driver activation and helper approval paths.

7) **Remove legacy polling layer**
   - After state-machine adoption, drop the background monitor loop and let users pull-to-refresh; if background checks are needed, run low-frequency, cancellable, and versioned to the latest snapshot.

8) **Documentation + rollout**
   - Update wizard README to reflect the unified stack and façade rules.
   - Gate rollout behind a feature flag; run side-by-side A/B (old vs new navigator) for a week, then delete legacy code paths.

## Success Criteria
- Same snapshot → same page and same plan every time (determinism tests pass).
- All system mutations pass through `InstallerEngine`; no direct helper/driver/service calls from UI.
- No fixed sleeps in wizard code; readiness checks only.
- Navigation and summary lists are derived from a single pure router.
