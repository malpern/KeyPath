# Installer Repair State Matrix

This checklist exists to prevent the recurring installer/repair loop where one
layer reports success while another layer is still stale, stopped, pending
approval, or using old diagnostic evidence.

Use it before changing installer, repair, permission, session runtime, or CLI
system-status code. KeyPath has one runtime, Kanata in a user-session worker
launched from KeyPath.app; there is no backend to choose (ADR-047).

## Core Rule

Installer success means the requested end state was proven, not that a command
ran.

For Kanata runtime mutations, the only successful final states are:

- `ready`: the session worker's tap is active, the process is live, and TCP is
  responding.
- `user action required`: macOS needs the user to grant KeyPath's
  Accessibility permission, and the report tells callers to stop retrying and
  show the manual step.
- `failed with diagnostics`: the action failed and reports the state that could
  not be proven.

Do not report success from proxy evidence such as file existence, a launched
process that never reported, or old log-derived diagnosis.

## Vocabulary

| Term | Meaning | Evidence |
|------|---------|----------|
| `running` | the session worker exists and its tap is active | the current worker report, through `ServiceHealthChecker` |
| `responding` | Kanata TCP server answers | `ServiceHealthChecker` TCP probe |
| `ready` | runtime can actually be used | `running && responding` |
| `input capture ready` | the worker can read and post keys | the current worker report (`PermissionOracle.Snapshot.runtimeKeyAccess`) |
| `payload present` | the bundle holds the host bridge and engine | `ComponentStatus.requiredRuntimePayloadPresent` |

## Evidence Hierarchy

When signals disagree, prefer evidence in this order:

1. Current runtime readiness: `running + engine socket responding`.
2. KeyPath's current Accessibility grant and the runtime's key-access report.
3. Bundled payload (file) existence.
4. Old logs, cached issue strings, restart-window heuristics.

Old diagnostic evidence may explain the last failure, but it must not override a
current missing/stopped runtime.

## State Matrix

The session runtime has two states. The rows for the retired privileged stack
(helper, LaunchDaemon, VirtualHID) were removed with that stack, and the
backend switch with them (ADR-047); see git history for them.

| State | Typical Evidence | Planner Should | Success Postcondition | Test Requirement |
|-------|------------------|----------------|-----------------------|------------------|
| Session runtime stopped or not ready | Current tap/process/engine socket or bundled payload evidence is missing | Start/recover through the session lifecycle owner; request Accessibility only if needed | Current tap active, process live, engine socket responding and bundled payload present; otherwise explicit failure or user action | Session golden fixture, plus unknown-capture and missing-payload rejection |
| Session tap active and engine responding | Current independently verified tap, process, engine socket and bundled payload | Nothing to install or repair | Runtime ready | Session ready golden fixture |

## Uninstall

`SessionUninstallCoordinator` removes only the current user's installation:
it stops the session workers, removes the login item, and moves KeyPath's
configuration, support files, caches, and the app to the Trash after a settings
backup. It runs no privileged cleanup and no administrator script. It reports
success only when no session worker remains running; an unreadable process
table is `unverified`, not success.

## Review Checklist

For any installer or repair change, answer these before merging:

- Which state-matrix row does this change affect?
- What proxy signal might be mistaken for success?
- What is the final state this path proves: `ready`, `user action required`,
  or `failed with diagnostics`?
- Does any path reintroduce a privileged helper, LaunchDaemon, or
  administrator script? It must not.
- Does every installer/repair report include structured telemetry for the
  trigger, state-matrix row, matrix plan/action, and postcondition result?
  `InstallerEngineTests.testExecuteRecordsStructuredRepairTelemetryForSuccessfulRecipe`,
  `InstallerEngineTests.testExecuteRecordsStructuredRepairTelemetryForFailedRecipe`,
  `InstallerEngineTests.testExecuteRecordsStructuredRepairTelemetryForNoopPlan`,
  `InstallerEngineTests.testExecuteHandlesBlockedPlan`, and
  `CLIOutputContractTests.testInstallerReportRepairTelemetryJSONShape` enforce
  the report/CLI contract.
- If the planner uses a diagnostic string, is that diagnostic scoped to a live
  current runtime?
- Does the CLI/UI report manual macOS approval as terminal user action rather
  than retryable autofix?
- Is there at least one planner test and one postcondition/router test for the
  affected state?

## Common Failure Patterns

### Stale Logs Treated As Current Cause

A stale `kanataInputCaptureIssue` can be true historically but wrong for the
current state. If Kanata is stopped or missing, runtime install/start comes
first. Re-evaluate input capture after runtime readiness is restored.

### Command Success Treated As Repair Success

Launching a session worker is a mutation attempt. It is not a success
criterion. The engine must prove the resulting state from the worker's current
report and the TCP probe.

### Manual Approval Treated As Retryable Autofix

When macOS requires user approval, stop the repair loop. The report should mark
the result as user action required and name the approval surface.

## Where To Put Enforcement

- Planning is `InstallerEngine.actions(for:context:)`: install and repair start
  the session runtime when it is not ready, and nothing else. The readiness rule
  is `SystemContext.installerStateMatrixRow`. Pure wizard logic tests pin both.
- There is no privileged command routing: the retired router, helper, and
  daemon managers were deleted in ADR-047 step 2e. Session runtime start, stop,
  and restart belong to `ServiceLifecycleCoordinator`.
- Runtime readiness checks belong in `ServiceHealthChecker` and
  `SystemStateProvider`'s shared lifecycle predicates.
- CLI `system inspect` reports the shared state-matrix classification and plan.
  `CLIOutputContractTests.testInspectResultRepairMetadataJSONShape` pins the
  JSON contract so CLI consumers see the same row/action vocabulary as the
  golden state-matrix planner.
- Menu-bar health uses the shared state-matrix row once app validation has
  classified the current system state. `MainAppStateControllerTests.menuBarHealthPrefersStateMatrixRow`
  pins that `runningAndTCPResponding` is the only matrix row treated as healthy
  by the compact status surface.
- Wizard detection results publish the shared state-matrix row and plan next to
  legacy wizard state/issues/actions. `WizardPureLogicTests.test_systemStateProjectionPublishesStateMatrixMetadata`
  pins the projection contract, while
  `WizardPureLogicTests.test_systemContextStateMatrixSnapshot_classifiesStoppedRuntimeWithStaleInputCapture`
  pins the pure `SystemContext` snapshot bridge used by wizard core.
- Raw process-liveness semantics live in `KeyPathSystemProbes` and are exposed
  to consumers through `SystemStateProvider.isProcessAlive(pid:)`.
  `SystemStateProviderLivenessTests.testProcessLivenessProbeTreatsCurrentProcessAsAliveAndExitedProcessAsDead`
  proves the real ADR-040 primitive, and
  `LivenessPredicateLintTests.testKillZeroLivenessProbeIsCentralized` blocks
  new direct `kill(pid, 0)` probes outside the probe module.
- Raw TCP readiness semantics live in `KeyPathSystemProbes` and are exposed to
  consumers through `SystemStateProvider.isTCPPortResponding(port:timeoutMs:)`.
  `SystemStateProviderLivenessTests.testTCPReadinessProbeDetectsListeningAndClosedPorts`
  proves the real localhost primitive,
  `TCPReadinessLintTests.testServiceHealthCheckerDelegatesTCPReadinessToSystemStateProvider`
  blocks `ServiceHealthChecker` from regrowing a private socket probe, and
  `TCPReadinessLintTests.testProductionTCPProbeAdapterIsNoLongerUsed` plus
  `TCPReadinessLintTests.testProductionRawTCPSocketProbeIsCentralized` block
  production readiness checks from bypassing the provider.
- Raw `pgrep` process discovery lives in `KeyPathSystemProbes`; consumers use
  `SystemStateProvider.processIDs(matching:)`,
  `SystemStateProvider.processMatches(matching:)`, or
  `SystemStateProvider.processIDsSynchronously(matching:)` for synchronous
  paths.
  `SystemStateProviderLivenessTests.testProcessDiscoveryDelegatesToInjectedSubprocessRunner`
  and `SystemStateProviderLivenessTests.testProcessDiscoveryRejectsBlankPatterns`
  pin the async provider contract,
  `SystemStateProviderLivenessTests.testProcessMatchDiscoveryDelegatesToInjectedSubprocessRunner`
  and `SystemStateProviderLivenessTests.testProcessMatchDiscoveryRejectsBlankPatterns`
  pin the command-aware provider contract,
  `SystemStateProviderLivenessTests.testSynchronousProcessDiscoveryRejectsBlankPatterns`
  and `SystemStateProviderLivenessTests.testSynchronousProcessDiscoveryReturnsEmptyForMissingProcess`
  pin the synchronous provider contract, while
  `PgrepProcessDiscoveryLintTests.testServiceLifecycleCoordinatorDelegatesPgrepDiscoveryToSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testSystemValidatorDelegatesPgrepDiscoveryToSystemStateProvider`,
  `DiagnosticsServiceTests.testKarabinerGrabberDetectionUsesInjectedSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testDiagnosticsServiceDelegatesPgrepDiscoveryToSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testKanataProcessDetectorDelegatesPgrepDiscoveryToSystemStateProvider`,
  and `PgrepProcessDiscoveryLintTests.testProductionPgrepDiscoveryIsCentralizedInCoreProvider`
  block runtime, system-validator, Karabiner-conflict, diagnostics and
  external-Kanata detection consumers from bypassing it.
- Nothing reads `launchctl print`: the session runtime has no launchd service.
  The probe chain that read it was removed with its tests (project review
  2026-11-09, B3).
- `SMAppService.status` is read only through an `SMAppServiceStatusProvider`
  (launch at login, `SMAppService.mainApp`). `SMAppServiceStatusProviderTests`
  pin its cache/coalescing contract, and
  `SMAppServiceStatusLintTests.testStatusAccessIsCentralized` blocks direct
  `.status` reads elsewhere.
- Permission snapshot reads belong behind `SystemStateProvider`'s façade over
  `PermissionOracle`.
  `SystemStateProviderPermissionTests.testPermissionSnapshotAccessDelegatesToPermissionOracle`
  and
  `SystemStateProviderPermissionTests.testPermissionSnapshotRefreshBypassesCachedSnapshot`
  cover the façade, while
  `PermissionSnapshotLintTests.testProductionPermissionSnapshotReadsDelegateToSystemStateProvider`
  scans all production sources and prevents new `PermissionOracle.shared`
  bypasses outside the provider façade.
- Repair entry points belong behind `InstallerEngine`. This is enforced by
  `FacadeLintTests.testProductionSourcesDoNotBypassInstallerEngine`.
- Installer recipes must be postcondition-verified before they report success:
  `InstallerEngine` checks each recipe's `expectedPostconditions` against the
  engine-owned final snapshot.
- Runtime and installer state caches must not regrow in consumers.
  `SnapshotConsumerLintTests.testRuntimeAndInstallerStateCachesStayInKnownOwners`
  prevents new runtime/installer state caches outside the current known owners.
  `W6DeletionPassLintTests.testAsyncRepairGatesDoNotConsumeUnboundedManagementStateCache`
  prevents async repair/start/reload gates from consuming the unbounded
  `currentManagementState` cache instead of refreshing through the
  provider-backed manager.
- User-facing CLI/reporting shape belongs in CLI contract tests.
- The state-matrix table itself is an executable golden fixture:
  `InstallerStateMatrixGoldenTests.testEveryDocumentedStateMatrixRowHasAGoldenFixture`
  requires one fixture per documented row, and
  `InstallerStateMatrixGoldenTests.testClassifySnapshotAndPlanMatchStateMatrixGoldenFixtures`
  asserts evidence in -> row out -> plan out for every row.
- Live state-matrix materialization is a pure projection of the canonical
  `SystemSnapshot` captured by `SystemValidator`; the deleted live-provider and
  wizard adapters must not be restored. `WizardPureLogicTests` pins projection
  and classification behavior, while
  `SnapshotConsumerLintTests.testInstallerEnginePreservesMatrixEvidenceThroughSystemSnapshotBridge`
  and `InstallerEngineLintTests` prevent duplicate recapture or planning paths.

## Related References

- `docs/adr/adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md`
- `docs/adr/adr-040-process-liveness-across-privilege-boundary.md`
- `docs/adr/adr-042-executable-installer-state-classification.md`
- `docs/bugs/2026-02-28-install-bundled-kanata-false-success-stale-throttle.md`
