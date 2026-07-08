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
| `registered` | SMAppService has registration metadata | `SMAppService.status`, through the shared status provider |
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

| State | Typical Evidence | Planner Should | Success Postcondition | Test Requirement |
|-------|------------------|----------------|-----------------------|------------------|
| Fresh install, missing components | Kanata binary, VHID driver, or required payload absent | Install missing components before runtime services | Components exist and next action is either runtime install or pending approval | Planner test for missing component order |
| Kanata not registered | SMAppService not found, no launchd job | Install/register runtime services | `ready` or explicit pending Login Items approval | Router/postcondition test for no false success |
| Registered but not loaded | `SMAppService.status == enabled`, launchd cannot find/load job | Bypass install throttle and recover registration | `ready` or explicit pending approval | Guard test for stale enabled registration bypassing throttle |
| Loaded but not running | launchd job exists, process absent | Reinstall/start runtime services, not VHID-only repair | `ready` | Planner test that missing/stopped Kanata schedules `installRequiredRuntimeServices` |
| Running but TCP not responding | process exists, TCP probe fails | Restart/recover Kanata runtime | `ready` or failed with TCP diagnostics | Postcondition test for timeout/failure when TCP stays down |
| Running and TCP responding | `ready == true` | No runtime repair unless another current issue exists | No-op or targeted non-runtime action | No-op planner test |
| Running but input capture failing | process exists, TCP responds, current input-capture issue | Repair VHID activation/services only after proving runtime is live | input capture ready, or pending VirtualHID approval, or failed with diagnostics | Planner test for live Kanata plus VHID activation issue |
| Stale/non-approval input-capture issue with Kanata stopped | cached/log issue exists, process absent, no explicit DriverKit approval-pending signal | Ignore stale issue for routing; install/start runtime services first | `ready` before reconsidering input capture | Regression test: stopped Kanata schedules runtime install instead of VHID-only repair |
| DriverKit approval pending with Kanata stopped | `inputCaptureVHIDDriverNotActivatedReason` and driver is installed | Stop retrying; surface manual approval before runtime repair | report marks user action required | Planner/CLI test that approval-pending returns no autofix loop |
| VirtualHID driver payload missing | VHID binaries/pkg payload missing | Install driver payload before registering VHID services | Payload present, services repaired, or manual approval | Helper/router test that launchd is not spawn-looped on missing payload |
| VHID services missing/unhealthy | daemon/manager plist or launchd health bad | Repair VHID services | VHID services loaded/healthy; Kanata `ready` if action also mutates runtime | VHID postcondition test after helper and sudo paths |
| VirtualHID approval pending | activation fails due to macOS approval | Stop retrying; surface manual action | report marks user action required | CLI JSON contract test for `userActionRequired` |
| Helper missing | helper not installed/responding | Install helper | helper installed and usable, or pending approval | Helper installation/approval test |
| Helper responds but may be stale | helper XPC works after helper behavior changed/deployed | Verify helper freshness or force unregister/register | helper fresh, then continue repair | HelperMaintenance force-refresh test |
| Helper path succeeds | helper reports operation success | Router must still verify postconditions | proven final state, not helper return value | Router test for helper success with failed postcondition |
| Sudo fallback succeeds | helper failed, sudo path reports success | Router must still verify same postconditions | proven final state, not fallback return value | Router test for sudo fallback postcondition |
| Manual approval is required | Login Items/System Extension/TCC approval needed | Return terminal manual-action state for this attempt | no retry loop; UI/CLI names approval | CLI/UI contract test |
| Definitive unhealthy state | repeated launchctl not-found, no process, no TCP | Fail with diagnostics, not optimistic success | failure report includes missing evidence | Failure-path test for no false green |

## Review Checklist

For any installer or repair change, answer these before merging:

- Which state-matrix row does this change affect?
- What proxy signal might be mistaken for success?
- What is the final state this path proves: `ready`, `pending approval`, or
  `failed with diagnostics`?
- Does every helper path and every sudo fallback path enforce the same
  postcondition?
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

- Planner routing belongs in `ActionDeterminer` and pure wizard logic tests.
- Privileged command routing belongs in `PrivilegedOperationsRouter`.
- Helper-owned root mutations belong in `HelperService`, but helper success must
  still be verified by the app-side router when possible.
- Runtime readiness checks belong in `ServiceHealthChecker` and
  `SystemStateProvider`'s shared lifecycle predicates.
- Process-liveness semantics belong in `SystemStateProvider.isProcessAlive(pid:)`.
  `SystemStateProviderLivenessTests.testProcessLivenessProbeTreatsCurrentProcessAsAliveAndExitedProcessAsDead`
  proves the real ADR-040 primitive, and
  `LivenessPredicateLintTests.testKillZeroLivenessProbeIsCentralized` blocks
  new direct `kill(pid, 0)` probes outside the provider.
- TCP readiness semantics belong in `SystemStateProvider.isTCPPortResponding(port:timeoutMs:)`.
  `SystemStateProviderLivenessTests.testTCPReadinessProbeDetectsListeningAndClosedPorts`
  proves the real localhost primitive,
  `TCPReadinessLintTests.testServiceHealthCheckerDelegatesTCPReadinessToSystemStateProvider`
  blocks `ServiceHealthChecker` from regrowing a private socket probe, and
  `TCPReadinessLintTests.testProductionTCPProbeAdapterIsNoLongerUsed` plus
  `TCPReadinessLintTests.testProductionRawTCPSocketProbeIsCentralized` block
  production readiness checks from bypassing the provider.
- `pgrep` process discovery belongs in `SystemStateProvider.processIDs(matching:)`,
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
  `KanataDaemonManagerTests.testRegisteredButNotLoadedUsesInjectedSystemStateProviderForProcessDiscovery`,
  `PgrepProcessDiscoveryLintTests.testServiceLifecycleCoordinatorDelegatesPgrepDiscoveryToSystemStateProvider`,
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
  `PgrepProcessDiscoveryLintTests.testLauncherServiceDelegatesPgrepDiscoveryToSystemStateProvider`,
  `ProcessLifecycleManagerTests.testDetectKanataProcessesUsesInjectedSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testProcessLifecycleManagerDelegatesPgrepDiscoveryToSystemStateProvider`,
  `PgrepProcessDiscoveryLintTests.testHelperServiceDelegatesPgrepDiscoveryToSystemStateProvider`,
  and `PgrepProcessDiscoveryLintTests.testProductionPgrepDiscoveryIsCentralizedInCoreProvider`
  block migrated runtime/system-validator/Karabiner-conflict/VHID/diagnostics/launcher/process-lifecycle/helper consumers from bypassing it.
- Read-only `launchctl print` service-state evidence belongs in
  `SystemStateProvider.launchctlPrint(target:)`; mutating launchctl operations
  remain installer/helper actions, not state reads.
  `SystemStateProviderLivenessTests.testLaunchctlPrintDelegatesToInjectedSubprocessRunner`
  and `SystemStateProviderLivenessTests.testLaunchctlPrintRejectsBlankTargets`
  pin the provider contract, while
  `VHIDDeviceManagerTests.testCheckLaunchctlHealthUsesInjectedSystemStateProvider`,
  `VHIDDeviceManagerTests.testDuplicateProcessRaceUsesInjectedLaunchctlEvidence`,
  and `LaunchctlEvidenceLintTests.testVHIDDeviceManagerDelegatesLaunchctlPrintEvidenceToSystemStateProvider`
  block migrated VirtualHID health checks from bypassing it.
  `ServiceHealthCheckerTests.testIsServiceLoadedDelegatesLaunchctlPrintToSystemStateProvider`,
  `ServiceHealthCheckerTests.testIsServiceHealthyDelegatesLaunchctlPrintToSystemStateProvider`,
  `ServiceHealthCheckerTests.testKanataRuntimeSnapshotDelegatesLaunchctlTargetsToSystemStateProvider`,
  and `LaunchctlEvidenceLintTests.testServiceHealthCheckerDelegatesLaunchctlPrintEvidenceToSystemStateProvider`
  block migrated service-health checks from bypassing it.
- User-facing CLI/reporting shape belongs in CLI contract tests.

## Related References

- `docs/adr/adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md`
- `docs/adr/adr-040-process-liveness-across-privilege-boundary.md`
- `docs/bugs/2026-02-28-install-bundled-kanata-false-success-stale-throttle.md`
