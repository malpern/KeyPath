# Installer Repair State Matrix

This checklist exists to prevent the recurring installer/repair loop where one
layer reports success while another layer is still stale, stopped, pending
approval, or using old diagnostic evidence.

Use it before changing installer, repair, helper, SMAppService, launchd,
permission, Kanata runtime, VirtualHID, or CLI system-status code.

## Core Rule

Installer success means the requested end state was proven, not that a command
ran.

For Kanata runtime mutations, the only successful final states are:

- `ready`: Kanata is running and TCP is responding.
- `pending approval`: macOS is explicitly waiting for user approval, and the
  report tells callers to stop retrying and show the manual step.
- `failed with diagnostics`: the action failed and reports the state that could
  not be proven.

Do not report success from proxy evidence such as helper responsiveness,
SMAppService registration, plist existence, a successful `launchctl` command, or
old stderr/log-derived diagnosis.

## Vocabulary

| Term | Meaning | Evidence |
|------|---------|----------|
| `registered` | SMAppService has registration metadata | `SMAppService.status`, through `SystemStateProvider`/the shared status provider |
| `loaded` | launchd can find the job | `ServiceHealthChecker` launchd/load evidence |
| `running` | the process exists | `ServiceHealthChecker` process/runtime snapshot |
| `responding` | Kanata TCP server answers | `ServiceHealthChecker` TCP probe |
| `ready` | runtime can actually be used | `running && responding` |
| `input capture ready` | Kanata can grab keyboard input | authoritative Kanata/InputGrab or current runtime evidence |
| `pending approval` | macOS requires user approval | SMAppService/Login Items or VirtualHID approval state surfaced as manual action |
| `helper fresh` | helper binary matches expected deployed behavior | version/path/timestamp evidence or forced unregister/register after helper deploy |

## Evidence Hierarchy

When signals disagree, prefer evidence in this order:

1. Current runtime readiness: `running + TCP responding`.
2. Explicit pending user approval.
3. Current launchd load/process evidence.
4. Current helper version/path/freshness evidence.
5. Registration metadata.
6. Plist/file existence.
7. Old logs, stderr tails, cached issue strings, restart-window heuristics.

Old diagnostic evidence may explain the last failure, but it must not override a
current missing/stopped runtime.

## State Matrix

The session runtime has two states. The rows for the retired privileged stack
(helper, LaunchDaemon, VirtualHID) were removed with that stack (ADR-047); see
git history for them.

| State | Typical Evidence | Planner Should | Success Postcondition | Test Requirement |
|-------|------------------|----------------|-----------------------|------------------|
| Session runtime stopped or not ready | Session backend; current tap/process/TCP or bundled payload evidence is missing | Start/recover through the session lifecycle owner; request AX then effective input approval only if needed | Current tap active, process live, TCP responding and bundled payload present; otherwise explicit failure/pending approval | Session golden fixture with absent optional driver/helper, plus unknown-capture and missing-payload rejection |
| Session tap active and TCP responding | Session backend; current independently verified tap, process, TCP and bundled payload | No helper/DriverKit install or repair | Runtime ready without inventing optional service health | Session ready golden fixture with absent optional driver/helper |

## Uninstall State Matrix

These coordinator states are intentionally separate from
`InstallerStateMatrixRow`: they describe an explicit uninstall transaction, not
a passive system-snapshot classification.

| State | Typical Evidence | Coordinator Should | Success Postcondition | Test Requirement |
|-------|------------------|--------------------|-----------------------|------------------|
| Uninstall helper missing or unresponsive | helper is absent or XPC health check fails | Repair/register the helper with `SMAppService`, verify XPC, then uninstall through the helper | KeyPath files and service registrations are absent | Coordinator test that helper repair precedes uninstall and no admin-script fallback runs automatically |
| Uninstall helper cannot be repaired | helper repair fails or still does not answer over XPC | Stop and return explicit `emergency-cleanup` recovery; never launch the admin script automatically | failed with diagnostics and a user-selected recovery action | Coordinator test that fallback invocation count remains zero until explicitly enabled |
| Uninstall including VirtualHID | user selected driver removal | Remove and verify the driver before the helper self-destructs; stop before removing KeyPath if the requested driver removal fails | KeyPath and DriverKit extension absent, or KeyPath remains installed with actionable driver diagnostics | Coordinator ordering and stop-before-app-removal tests |
| Emergency uninstall cleanup | user explicitly confirms Emergency Cleanup | Run the bundled cleanup script with administrator authorization and verify the same postconditions | requested files, registrations, and optional driver are absent | Test that command success with failed postconditions remains failure |

## Review Checklist

For any installer or repair change, answer these before merging:

- Which state-matrix row does this change affect?
- What proxy signal might be mistaken for success?
- What is the final state this path proves: `ready`, `pending approval`, or
  `failed with diagnostics`?
- Does every helper path and every sudo fallback path enforce the same
  postcondition?
- Can any uninstall path launch administrator-script fallback without a separate,
  explicit user action? It must not.
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
- If helper code changed, how is helper freshness verified after deploy?
- Does the CLI/UI report manual macOS approval as terminal user action rather
  than retryable autofix?
- Is there at least one planner test and one postcondition/router test for the
  affected state?

## Common Failure Patterns

### Registration Treated As Liveness

`SMAppService.status == enabled` only proves metadata. It does not prove launchd
can load the job, that a process exists, or that TCP is responding.

### Helper Response Treated As Freshness

An old helper can respond over XPC after the app bundle has changed. After helper
deploys or helper behavior changes, force the unregister/register path or verify
freshness explicitly.

### Stale Logs Treated As Current Cause

A stale `kanataInputCaptureIssue` can be true historically but wrong for the
current state. If Kanata is stopped or missing, runtime install/start comes
first. Re-evaluate input capture after runtime readiness is restored.

### Command Success Treated As Repair Success

`launchctl bootstrap`, `kickstart`, helper replies, and sudo command batches are
mutation attempts. They are not success criteria. The router or engine must prove
the resulting state.

### Manual Approval Treated As Retryable Autofix

When macOS requires user approval, stop the repair loop. The report should mark
the result as user action required and name the approval surface.

## Where To Put Enforcement

- Planner routing belongs in `InstallerDecisionPipeline` and pure wizard logic
  tests.
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
  pre-exec/privileged-helper paths.
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
  `PgrepProcessDiscoveryLintTests.testLauncherServiceDelegatesPgrepDiscoveryToSystemStateProvider`,
  `ProcessLifecycleManagerTests.testDetectKanataProcessesUsesInjectedSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testProcessLifecycleManagerDelegatesPgrepDiscoveryToSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testHelperServiceDelegatesPgrepDiscoveryToSystemStateProvider`,
  and `PgrepProcessDiscoveryLintTests.testProductionPgrepDiscoveryIsCentralizedInCoreProvider`
  block migrated runtime/system-validator/Karabiner-conflict/VHID/diagnostics/launcher/process-lifecycle/helper consumers from bypassing it.
- Read-only `launchctl print` service-state evidence belongs in
  `KeyPathSystemProbes` and is exposed through
  `SystemStateProvider.launchctlPrint(target:)`.
  `SystemStateProviderLivenessTests.testLaunchctlPrintDelegatesToInjectedSubprocessRunner`
  and `SystemStateProviderLivenessTests.testLaunchctlPrintRejectsBlankTargets`
  pin the provider contract, and
  `LaunchctlEvidenceLintTests.testProductionLaunchctlPrintEvidenceReadsDelegateToSystemStateProvider`
  blocks new direct reads.
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
  and `InstallerDecisionPipelineLintTests` prevent duplicate recapture or
  planning paths.

## Related References

- `docs/adr/adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md`
- `docs/adr/adr-040-process-liveness-across-privilege-boundary.md`
- `docs/adr/adr-042-executable-installer-state-classification.md`
- `docs/bugs/2026-02-28-install-bundled-kanata-false-success-stale-throttle.md`
