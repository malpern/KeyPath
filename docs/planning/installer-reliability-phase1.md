# Installer Reliability Phase 1: Foundation Before Autonomy

**Status:** Proposed
**Date:** 2026-07-06
**Companion:** [autonomous-repair-roadmap.md](autonomous-repair-roadmap.md) (Phase 2 — deferred, not abandoned)

## Purpose

For 18 months the installer/repair subsystem has cycled: stable → unstable →
repaired → unstable. Analysis of ~356 commits, the bug docs, and the ADRs shows
the loop was driven primarily by architecture (fragmented repair paths, proxy
evidence treated as success, 167+ scattered state-inspection points reading
through 8 caches with 5 different TTLs), not by macOS hostility. macOS supplied
the raw material; the architecture multiplied it.

Phase 1 makes the core incredibly reliable by following the industry-standard
pattern for privileged-component apps (Rogue Amoeba, Karabiner-Elements,
Keyboard Maestro):

> **Install once → detect cheaply and continuously → repair only on user
> action, one shot, with proven postconditions → escalate the unfixable tail
> to guided manual steps.**

Continuous *autonomous* repair is explicitly out of scope for Phase 1. It is a
real ambition — see the roadmap doc — but it is gated on this foundation
existing and holding stable first.

## Scope

**In scope (Phase 1):**
1. Executable state model (single source of truth for system state)
2. One blessed liveness/readiness predicate
3. Repair model: user-initiated, one-shot, postcondition-proven
4. Prevention at the source (signing/path/identity stability)
5. Lint-test ratchets that make the invariants structural
6. Deletion pass (redundancy, dead abstraction, cache zoo)

**Out of scope (Phase 1, deferred to Phase 2):**
- Watchdog-triggered automatic repair of any kind
- Retry budgets, repair throttles, restart-window heuristics that exist only
  to keep autonomous repair from fighting itself
- Background "self-healing" behaviors beyond what launchd itself provides
  (`KeepAlive` remains; it is OS-level, not app logic)

## Workstream 1: Executable State Matrix

The [installer repair state matrix](../process/installer-repair-state-matrix.md)
is currently a *document* — a checklist humans and agents must remember to
apply. Checklists decay; that is how the loop happened. Make it code.

**Deliverables:**
- A single `SystemStateProvider` actor that owns **every** OS-level evidence
  query: `launchctl print`, `SMAppService.status` (via the existing
  `SMAppServiceStatusProvider`), process liveness, TCP probes, TCC/permission
  state (via `PermissionOracle`), VHID driver/daemon state, helper freshness.
- It emits one immutable `SystemSnapshot` value. All caching lives inside the
  provider (target: one TTL policy, one bulk-invalidation point fired on any
  mutation). Nothing above the provider caches.
- A pure function `classify(snapshot) -> StateMatrixRow` that maps a snapshot
  to exactly one row of the state matrix, and a pure
  `plan(row) -> [RepairAction]`. The planner, `PrivilegedOperationsRouter`,
  wizard routing, CLI `system-status`, and menu-bar indicator all consume the
  same snapshot and the same classification.
- The state matrix table in the process doc becomes a **test fixture**: one
  table-driven test asserting `classify`/`plan` output per row, replacing
  review-checklist enforcement with compile-time/test-time enforcement.

**Acceptance criteria:**
- Zero direct `launchctl`/`SMAppService.status`/`pgrep`/TCP-probe calls outside
  the provider (enforced by lint tests, Workstream 5).
- Every state-matrix row has a golden test: evidence in → row out → plan out.
- Wizard, CLI, and menu bar cannot disagree about system state because they
  cannot read different sources.

**Status (2026-07-07):** First provider slices implemented; full snapshot
classification remains pending.
- [x] Introduced `SystemStateProvider` as the owner for the ADR-040
  process-liveness primitive and Kanata readiness predicate. Enforced by
  `SystemStateProviderLivenessTests.testProcessLivenessProbeTreatsCurrentProcessAsAliveAndExitedProcessAsDead`
  and `SystemStateProviderLivenessTests.testKanataReadinessRequiresRunningAndResponding`.
- [x] Moved the TCP readiness primitive into `SystemStateProvider` and migrated
  `ServiceHealthChecker` to delegate to it. Enforced by
  `SystemStateProviderLivenessTests.testTCPReadinessProbeDetectsListeningAndClosedPorts`,
  `SystemStateProviderLivenessTests.testTCPReadinessRejectsInvalidPorts`, and
  `TCPReadinessLintTests.testServiceHealthCheckerDelegatesTCPReadinessToSystemStateProvider`.
- [x] Migrated remaining production `TCPProbe.probe` consumers to
  `SystemStateProvider`. Enforced by
  `TCPReadinessLintTests.testProductionTCPProbeAdapterIsNoLongerUsed` and
  `TCPReadinessLintTests.testProductionRawTCPSocketProbeIsCentralized`.
- [x] Added provider-owned `pgrep` process-discovery primitive and migrated
  `ServiceLifecycleCoordinator`, `KanataDaemonManager`, and `SystemValidator`
  to delegate to it. Started migrating Karabiner conflict detection as a
  follow-on process-discovery slice. Enforced by
  `SystemStateProviderLivenessTests.testProcessDiscoveryDelegatesToInjectedSubprocessRunner`,
  `SystemStateProviderLivenessTests.testProcessDiscoveryRejectsBlankPatterns`,
  `PgrepProcessDiscoveryLintTests.testServiceLifecycleCoordinatorDelegatesPgrepDiscoveryToSystemStateProvider`,
  `KanataDaemonManagerTests.testRegisteredButNotLoadedUsesInjectedSystemStateProviderForProcessDiscovery`,
  `PgrepProcessDiscoveryLintTests.testKanataDaemonManagerDelegatesPgrepDiscoveryToSystemStateProvider`,
  `SystemValidatorTests.karabinerGrabberPIDUsesInjectedSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testSystemValidatorDelegatesPgrepDiscoveryToSystemStateProvider`,
  `KarabinerConflictServiceTests.karabinerGrabberDetectionUsesInjectedSystemStateProvider`,
  `KarabinerConflictServiceTests.virtualHIDDaemonDetectionUsesInjectedSystemStateProvider`,
  `KarabinerConflictServiceTests.stoppedProcessVerificationUsesInjectedSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testKarabinerConflictServiceDelegatesPgrepDiscoveryToSystemStateProvider`,
  `VHIDDeviceManagerTests.testDetectRunningUsesInjectedSystemStateProviderForProcessDiscovery`,
  `VHIDDeviceManagerTests.testGetDaemonPIDsUsesInjectedSystemStateProviderForProcessDiscovery`,
  `PgrepProcessDiscoveryLintTests.testVHIDDeviceManagerDelegatesPgrepDiscoveryToSystemStateProvider`,
  `DiagnosticsServiceTests.testKarabinerGrabberDetectionUsesInjectedSystemStateProvider`,
  `DiagnosticsServiceTests.testKarabinerDaemonDetectionUsesInjectedSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testDiagnosticsServiceDelegatesPgrepDiscoveryToSystemStateProvider`,
  `SystemStateProviderLivenessTests.testSynchronousProcessDiscoveryRejectsBlankPatterns`,
  `SystemStateProviderLivenessTests.testSynchronousProcessDiscoveryReturnsEmptyForMissingProcess`,
  `PgrepProcessDiscoveryLintTests.testLauncherServiceDelegatesPgrepDiscoveryToSystemStateProvider`,
  `SystemStateProviderLivenessTests.testProcessMatchDiscoveryDelegatesToInjectedSubprocessRunner`,
  `SystemStateProviderLivenessTests.testProcessMatchDiscoveryRejectsBlankPatterns`,
  `ProcessLifecycleManagerTests.testDetectKanataProcessesUsesInjectedSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testProcessLifecycleManagerDelegatesPgrepDiscoveryToSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testHelperServiceDelegatesPgrepDiscoveryToSystemStateProvider`,
  and `PgrepProcessDiscoveryLintTests.testProductionPgrepDiscoveryIsCentralizedInCoreProvider`.
- [x] Added provider-owned `launchctl print` service-state evidence and migrated
  `VHIDDeviceManager`'s read-only VirtualHID launchd health checks to delegate
  to it. Enforced by
  `SystemStateProviderLivenessTests.testLaunchctlPrintDelegatesToInjectedSubprocessRunner`,
  `SystemStateProviderLivenessTests.testLaunchctlPrintRejectsBlankTargets`,
  `VHIDDeviceManagerTests.testCheckLaunchctlHealthUsesInjectedSystemStateProvider`,
  `VHIDDeviceManagerTests.testDuplicateProcessRaceUsesInjectedLaunchctlEvidence`,
  and
  `LaunchctlEvidenceLintTests.testVHIDDeviceManagerDelegatesLaunchctlPrintEvidenceToSystemStateProvider`.
- [x] Migrated `ServiceHealthChecker`'s read-only `launchctl print` loaded,
  health, and Kanata runtime-snapshot evidence to
  `SystemStateProvider.launchctlPrint(target:)`. Enforced by
  `ServiceHealthCheckerTests.testIsServiceLoadedDelegatesLaunchctlPrintToSystemStateProvider`,
  `ServiceHealthCheckerTests.testIsServiceHealthyDelegatesLaunchctlPrintToSystemStateProvider`,
  `ServiceHealthCheckerTests.testKanataRuntimeSnapshotDelegatesLaunchctlTargetsToSystemStateProvider`,
  and
  `LaunchctlEvidenceLintTests.testServiceHealthCheckerDelegatesLaunchctlPrintEvidenceToSystemStateProvider`.
- [ ] Migrate `launchctl`, `SMAppService.status`, permissions, VHID state, and
  helper freshness into a single immutable `SystemSnapshot`.
- [ ] Build `classify(snapshot) -> StateMatrixRow -> plan` and table-driven
  golden tests for every state-matrix row.

## Workstream 2: One Liveness Predicate

Today there are 10+ independent implementations of "is kanata running" across
`ServiceHealthChecker`, `KanataDaemonService`, `KanataDaemonManager`,
`ProcessLifecycleManager`, `SystemValidator`, and others, each with different
fallback ordering and cache TTLs. Every one is a place the next regression can
live (see ADR-040: the EPERM-across-privilege-boundary trap shipped green
through 21 mocked tests).

**Deliverables:**
- One blessed readiness predicate inside the provider:
  `ready = running (ESRCH-only-means-dead, per ADR-040) && TCP responding`.
- One blessed `registered` / `loaded` / `running` / `responding` vocabulary
  implementation matching ADR-031, used everywhere.
- All other implementations delegate or are deleted.

**Acceptance criteria:**
- `kill(pid, 0)` / process-probe logic exists in exactly one function.
- A grounding test runs the real primitive against a known-alive pid
  (`getpid()`) and a known-dead pid (ADR-040 §3), not only mocked seams.

**Status (2026-07-07):** First liveness/readiness predicate slices implemented.
- [x] `kill(pid, 0)` liveness semantics exist in exactly one production
  function, `SystemStateProvider.isProcessAlive(pid:)`. Enforced by
  `LivenessPredicateLintTests.testKillZeroLivenessProbeIsCentralized`.
- [x] The real primitive is tested against `getpid()` and an exited child
  process. Enforced by
  `SystemStateProviderLivenessTests.testProcessLivenessProbeTreatsCurrentProcessAsAliveAndExitedProcessAsDead`.
- [x] Kanata readiness is pinned to `running && responding`. Enforced by
  `SystemStateProviderLivenessTests.testKanataReadinessRequiresRunningAndResponding`.
- [x] TCP readiness has a provider-owned primitive with a real local listener
  grounding test. Enforced by
  `SystemStateProviderLivenessTests.testTCPReadinessProbeDetectsListeningAndClosedPorts`
  and `SystemStateProviderLivenessTests.testTCPReadinessRejectsInvalidPorts`.
- [x] Remaining production TCP readiness consumers delegate to
  `SystemStateProvider`. Enforced by
  `TCPReadinessLintTests.testProductionTCPProbeAdapterIsNoLongerUsed`.
- [x] `ServiceLifecycleCoordinator` process discovery delegates to
  `SystemStateProvider.processIDs(matching:)`. Enforced by
  `PgrepProcessDiscoveryLintTests.testServiceLifecycleCoordinatorDelegatesPgrepDiscoveryToSystemStateProvider`.
- [x] `KanataDaemonManager` process discovery delegates to
  `SystemStateProvider.processIDs(matching:)`. Enforced by
  `KanataDaemonManagerTests.testRegisteredButNotLoadedUsesInjectedSystemStateProviderForProcessDiscovery`
  and
  `PgrepProcessDiscoveryLintTests.testKanataDaemonManagerDelegatesPgrepDiscoveryToSystemStateProvider`.
- [x] `SystemValidator` process discovery delegates to
  `SystemStateProvider.processIDs(matching:)`. Enforced by
  `SystemValidatorTests.karabinerGrabberPIDUsesInjectedSystemStateProvider`
  and
  `PgrepProcessDiscoveryLintTests.testSystemValidatorDelegatesPgrepDiscoveryToSystemStateProvider`.
- [x] `KarabinerConflictService` process discovery delegates to
  `SystemStateProvider.processIDs(matching:)`. Enforced by
  `KarabinerConflictServiceTests.karabinerGrabberDetectionUsesInjectedSystemStateProvider`,
  `KarabinerConflictServiceTests.virtualHIDDaemonDetectionUsesInjectedSystemStateProvider`,
  `KarabinerConflictServiceTests.stoppedProcessVerificationUsesInjectedSystemStateProvider`,
  and
  `PgrepProcessDiscoveryLintTests.testKarabinerConflictServiceDelegatesPgrepDiscoveryToSystemStateProvider`.
- [x] `VHIDDeviceManager` process discovery delegates to
  `SystemStateProvider.processIDs(matching:)`. Enforced by
  `VHIDDeviceManagerTests.testDetectRunningUsesInjectedSystemStateProviderForProcessDiscovery`,
  `VHIDDeviceManagerTests.testGetDaemonPIDsUsesInjectedSystemStateProviderForProcessDiscovery`,
  and
  `PgrepProcessDiscoveryLintTests.testVHIDDeviceManagerDelegatesPgrepDiscoveryToSystemStateProvider`.
- [x] `DiagnosticsService` process discovery delegates to
  `SystemStateProvider.processIDs(matching:)`. Enforced by
  `DiagnosticsServiceTests.testKarabinerGrabberDetectionUsesInjectedSystemStateProvider`,
  `DiagnosticsServiceTests.testKarabinerDaemonDetectionUsesInjectedSystemStateProvider`,
  and
  `PgrepProcessDiscoveryLintTests.testDiagnosticsServiceDelegatesPgrepDiscoveryToSystemStateProvider`.
- [x] `LauncherService` synchronous process discovery delegates to
  `SystemStateProvider.processIDsSynchronously(matching:)`. Enforced by
  `SystemStateProviderLivenessTests.testSynchronousProcessDiscoveryRejectsBlankPatterns`,
  `SystemStateProviderLivenessTests.testSynchronousProcessDiscoveryReturnsEmptyForMissingProcess`,
  and
  `PgrepProcessDiscoveryLintTests.testLauncherServiceDelegatesPgrepDiscoveryToSystemStateProvider`.
- [x] `ProcessLifecycleManager` command-aware process discovery delegates to
  `SystemStateProvider.processMatches(matching:)`. Enforced by
  `SystemStateProviderLivenessTests.testProcessMatchDiscoveryDelegatesToInjectedSubprocessRunner`,
  `SystemStateProviderLivenessTests.testProcessMatchDiscoveryRejectsBlankPatterns`,
  `ProcessLifecycleManagerTests.testDetectKanataProcessesUsesInjectedSystemStateProvider`,
  and
  `PgrepProcessDiscoveryLintTests.testProcessLifecycleManagerDelegatesPgrepDiscoveryToSystemStateProvider`.
- [x] `HelperService` synchronous privileged-helper process discovery delegates
  to `SystemStateProvider.processIDsSynchronously(matching:)`. Enforced by
  `SystemStateProviderLivenessTests.testSynchronousProcessDiscoveryRejectsBlankPatterns`,
  `SystemStateProviderLivenessTests.testSynchronousProcessDiscoveryReturnsEmptyForMissingProcess`,
  and
  `PgrepProcessDiscoveryLintTests.testHelperServiceDelegatesPgrepDiscoveryToSystemStateProvider`.
- [x] Production `pgrep` process discovery is centralized in
  `SystemStateProvider`/`SubprocessRunner`, with no caller-owned production
  uses remaining. Enforced by
  `PgrepProcessDiscoveryLintTests.testProductionPgrepDiscoveryIsCentralizedInCoreProvider`.
- [x] `VHIDDeviceManager` read-only `launchctl print` service-state evidence
  delegates to `SystemStateProvider.launchctlPrint(target:)`. Enforced by
  `SystemStateProviderLivenessTests.testLaunchctlPrintDelegatesToInjectedSubprocessRunner`,
  `SystemStateProviderLivenessTests.testLaunchctlPrintRejectsBlankTargets`,
  `VHIDDeviceManagerTests.testCheckLaunchctlHealthUsesInjectedSystemStateProvider`,
  `VHIDDeviceManagerTests.testDuplicateProcessRaceUsesInjectedLaunchctlEvidence`,
  and
  `LaunchctlEvidenceLintTests.testVHIDDeviceManagerDelegatesLaunchctlPrintEvidenceToSystemStateProvider`.
- [x] `ServiceHealthChecker` read-only `launchctl print` loaded, health, and
  runtime-snapshot evidence delegates to
  `SystemStateProvider.launchctlPrint(target:)`. Enforced by
  `ServiceHealthCheckerTests.testIsServiceLoadedDelegatesLaunchctlPrintToSystemStateProvider`,
  `ServiceHealthCheckerTests.testIsServiceHealthyDelegatesLaunchctlPrintToSystemStateProvider`,
  `ServiceHealthCheckerTests.testKanataRuntimeSnapshotDelegatesLaunchctlTargetsToSystemStateProvider`,
  and
  `LaunchctlEvidenceLintTests.testServiceHealthCheckerDelegatesLaunchctlPrintEvidenceToSystemStateProvider`.

## Workstream 3: Industry-Standard Repair Model

Adopt detect → surface → user-initiated repair → escalate. This matches what
every comparable product does (Karabiner-Elements: menu-item service restart;
Rogue Amoeba ACE: Repair button that reinstalls and re-verifies; Keyboard
Maestro/Hammerspoon: documented manual TCC recovery), and it deletes the
hardest-to-keep-stable code we own, because throttles, restart windows, and
retry budgets exist only to stop *autonomous* repair from fighting itself.

**Deliverables:**
- **Detection stays continuous but becomes passive and cheap:** the provider
  refreshes its snapshot on a modest cadence and on lifecycle events; the UI
  (menu bar, wizard, CLI) *surfaces* degraded state. Detection never mutates.
- **Repair is a single user-initiated action** ("Repair" button / CLI verb)
  that runs `InstallerEngine.run(intent: .repair)` once, enforces the ADR-031
  postcondition (`ready`, `pending approval`, or `failed with diagnostics` —
  nothing else), and reports honestly.
- **Manual-approval states are terminal for the attempt** (already the rule;
  keep it): pending Login Items / DriverKit approval / TCC grant renders as a
  guided step with the exact System Settings surface named, never a retry.
- **The unfixable tail gets documentation, not code:** BTM corruption
  (`sfltool resetbtm` + reboot), Tahoe driver-approval loops, endpoint-security
  software blocking the dext, TCC.db desync. A troubleshooting guide per
  failure class, linked directly from the failure report that detected it.
- Remove (or reduce to trivial) the machinery that only served autonomy:
  generic install throttle, stale-recovery throttle bypass special-casing,
  restart-window "healthy-ish" heuristics, watchdog-triggered fix attempts.
  Where a piece must stay for Phase 1 (e.g. first-run wizard auto-fix of
  missing components), document why in the code.

**What the wizard keeps:** the rich first-run install flow is KeyPath's
differentiator (it automates the 3-LaunchDaemon + 2-TCC-grant manual setup
every kanata-on-macOS user otherwise does by hand) and is unchanged in spirit.
Phase 1 changes *post-install* behavior, not first-run automation.

**Acceptance criteria:**
- No code path mutates system services without a user gesture (first-run
  wizard flows count as user gestures; background watchdogs do not).
- Every repair path (helper and sudo fallback alike) proves the same
  postcondition before reporting success (state-matrix "Helper path succeeds" /
  "Sudo fallback succeeds" rows).
- Every terminal failure report names either the manual approval surface or
  the troubleshooting doc for its failure class.

## Workstream 4: Prevention at the Source

Much of the repair demand is TCC/identity flap we can prevent instead of
handle. Mechanically, permission loss comes from: (1) code-signature /
designated-requirement changes on update, (2) binary path changes,
(3) TCC.db/BTM cache desync, (4) OS regressions. (1) and (2) are ours to fix;
(3) and (4) are Workstream 3's escalation docs.

**Deliverables:**
- An **identity-stability audit + contract test**: the bundled kanata's bundle
  ID, signing identifier, designated requirement, and canonical installed path
  (ADR-032/033/034) must be byte-stable across app updates. A release-gate
  test compares them against pinned expected values so an accidental change
  fails the build, not the user's Input Monitoring grant.
- Same for the privileged helper and daemon shells: signing-identifier
  stability guards against the launchd LWCR launch-constraint trap
  (constraints cached from the old version survive `unregister()`; only
  app-delete + reinstall clears them).

**Acceptance criteria:**
- Release doctor / CI verifies identity stability for kanata binary, helper,
  and daemon against pinned values.
- Documented in an ADR so future re-signing work knows the blast radius.

**Status (2026-07-06):** Implemented for Workstream 4.
- [x] Release doctor / CI verifies identity stability for kanata binary, helper,
  and daemon against pinned values. Enforced by
  `IdentityStabilityContractTests.testPinnedSourceIdentityContract`,
  `IdentityStabilityContractTests.testReleaseGateInvokesIdentityContractScript`,
  and `Scripts/verify-identity-contract.sh`.
- [x] Documented in an ADR so future re-signing work knows the blast radius.
  Enforced by `IdentityStabilityContractTests.testIdentityADRDocumentsPinnedContract`
  against `docs/adr/adr-041-installer-identity-stability-contract.md`.

## Workstream 5: Lint-Test Ratchets

`SMAppServiceStatusLintTests` (build fails if any source outside the provider
reads `.status`) is the best pattern in the codebase: enforcement that survives
context loss across sessions, contributors, and agents. Extend it:

| Ratchet | Rule |
|---------|------|
| `LaunchctlLintTests` | `launchctl` invocations only inside `SystemStateProvider`/`ServiceHealthChecker` |
| `LivenessLintTests` | `kill(`, `pgrep`, process-probe patterns only inside the blessed predicate |
| `PostconditionLintTests` | every `PrivilegedOperationsRouter` mutating verb calls the postcondition enforcer before returning success |
| `SnapshotConsumerLintTests` | no new caches of system state outside the provider (grep for TTL/timestamp-cache patterns) |

**Acceptance criteria:** each ratchet lands with the workstream it protects and
is listed in the state-matrix doc's enforcement section.

**Status (2026-07-07):** First liveness/readiness ratchets implemented.
- [x] `LivenessPredicateLintTests.testKillZeroLivenessProbeIsCentralized`
  prevents new direct `kill(pid, 0)` liveness probes outside
  `SystemStateProvider`.
- [x] `TCPReadinessLintTests.testServiceHealthCheckerDelegatesTCPReadinessToSystemStateProvider`
  prevents `ServiceHealthChecker` from regrowing a private TCP socket probe.
- [x] `TCPReadinessLintTests.testProductionTCPProbeAdapterIsNoLongerUsed` and
  `TCPReadinessLintTests.testProductionRawTCPSocketProbeIsCentralized` prevent
  production readiness checks from drifting back to the legacy adapter or raw
  socket probes outside `SystemStateProvider`.
- [x] `PgrepProcessDiscoveryLintTests.testServiceLifecycleCoordinatorDelegatesPgrepDiscoveryToSystemStateProvider`
  prevents the first migrated runtime coordinator call site from regrowing
  direct `pgrep` process discovery.
- [x] `PgrepProcessDiscoveryLintTests.testKanataDaemonManagerDelegatesPgrepDiscoveryToSystemStateProvider`
  prevents the daemon-management process discovery call site from regrowing
  direct `pgrep` process discovery.
- [x] `PgrepProcessDiscoveryLintTests.testSystemValidatorDelegatesPgrepDiscoveryToSystemStateProvider`
  prevents the system-validator process discovery call site from regrowing
  direct `pgrep` process discovery.
- [x] `PgrepProcessDiscoveryLintTests.testKarabinerConflictServiceDelegatesPgrepDiscoveryToSystemStateProvider`
  prevents Karabiner conflict detection from regrowing direct
  `pgrep` process discovery.
- [x] `PgrepProcessDiscoveryLintTests.testVHIDDeviceManagerDelegatesPgrepDiscoveryToSystemStateProvider`
  prevents VirtualHID daemon process checks from regrowing direct
  `pgrep` process discovery.
- [x] `PgrepProcessDiscoveryLintTests.testDiagnosticsServiceDelegatesPgrepDiscoveryToSystemStateProvider`
  prevents diagnostics process checks from regrowing direct
  `pgrep` process discovery.
- [x] `PgrepProcessDiscoveryLintTests.testLauncherServiceDelegatesPgrepDiscoveryToSystemStateProvider`
  prevents the launcher fallback from regrowing direct `pgrep` process
  discovery.
- [x] `PgrepProcessDiscoveryLintTests.testProcessLifecycleManagerDelegatesPgrepDiscoveryToSystemStateProvider`
  prevents command-aware Kanata process conflict detection from regrowing direct
  `pgrep` process discovery.
- [x] `PgrepProcessDiscoveryLintTests.testProductionPgrepDiscoveryIsCentralizedInCoreProvider`
  blocks production `pgrep` process discovery outside the core provider
  implementation.
- [x] `LaunchctlEvidenceLintTests.testVHIDDeviceManagerDelegatesLaunchctlPrintEvidenceToSystemStateProvider`
  prevents `VHIDDeviceManager` from regrowing direct `launchctl print`
  service-state reads.
- [x] `LaunchctlEvidenceLintTests.testServiceHealthCheckerDelegatesLaunchctlPrintEvidenceToSystemStateProvider`
  prevents `ServiceHealthChecker` from regrowing direct `launchctl print`
  service-state reads.
- [ ] Add remaining `launchctl`, postcondition, and snapshot-cache
  ratchets with the corresponding migration slices.

## Workstream 6: Deletion Pass

After Workstreams 1–3 land (not before — don't polish code about to be
removed):

- Delete the ~6 single-implementation protocols
  (`ConfigurationManaging`, `DiagnosticsManaging`, `KarabinerConflictManaging`,
  `ServiceHealthMonitorProtocol`, …) or make the coordinator actually hold the
  protocol type with an injected implementation. No protocol without ≥2
  implementations or genuine test injection.
- Remove duplicated in-path checks ("second safety layer" VHID check in
  `startKanata`, triple kanata-health checks in startup): pass the snapshot as
  a parameter instead of re-querying per layer.
- Collapse the cache zoo (healthCache / runtimeCache / serviceStatusCache /
  smAppServicePendingCache / cachedHelperVersion / cachedFDAStatus / …) into
  the provider.
- Replace DEBUG-only `nonisolated(unsafe)` test seams with initializer
  injection where practical (ADR-019 seams stay only for OS primitives that
  genuinely can't be injected, each with a grounding test per ADR-040).

**Target:** the subsystem is ~34K LOC (~19% of the app). A 25–35% reduction is
realistic without losing capability. Measure before/after.

## Sequencing

1. **W4 (prevention)** — independent, highest leverage per line, do first.
2. **W1 + W2 (provider + predicate)** — the structural core. Land provider,
   migrate consumers incrementally behind lint ratchets (W5 lands with each
   migration).
3. **W3 (repair model)** — once all consumers read one snapshot, removing the
   autonomy-support machinery is safe and mostly deletion.
4. **W6 (deletion pass)** — last.

Each step keeps the full test suite green; state-matrix golden tests are the
regression net. No big-bang rewrite — the July 2026 closure commits
(postcondition enforcement, router consolidation, status provider) are the
foundation, not something to replace.

## Exit Criteria (gate for even *considering* Phase 2)

- All six workstreams' acceptance criteria met.
- State matrix fully executable and golden-tested.
- One sustained stability window (proposal: 2 release cycles / 8 weeks) with
  zero installer/repair regressions and zero false-green or false-alert
  incidents in the debug logs of dogfood machines.
- Repair success/failure outcomes are observable (structured log events for
  every repair attempt: trigger, row, action, postcondition result) — this
  telemetry is Phase 2's prerequisite data.

## Non-Goals Reminder

This plan deliberately walks back *when* repair runs, not *what* repair can
do. The full autonomous ambition — continuous validation, self-healing without
user interaction — is planned, gated, and preserved in
[autonomous-repair-roadmap.md](autonomous-repair-roadmap.md).

## References

- [Installer repair state matrix](../process/installer-repair-state-matrix.md)
- [ADR-031: lifecycle invariants & postcondition enforcement](../adr/adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md)
- [ADR-040: process liveness across the privilege boundary](../adr/adr-040-process-liveness-across-privilege-boundary.md)
- [ADR-032/033/034: runtime identity, canonical path, TCC identity](../adr/adr-032-macos-kanata-runtime-identity.md)
- [2026-02-28 false-success incident](../bugs/2026-02-28-install-bundled-kanata-false-success-stale-throttle.md)
- Industry references: Rogue Amoeba ACE repair flow; Karabiner-Elements v15
  SMAppService architecture and restart-service menu; Apple forums on stale
  SMAppService registrations (`sfltool resetbtm`) and LWCR launch-constraint
  caching across updates.
