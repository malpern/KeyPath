# Helper Health Probe Invalidated an Active Mutation

**Date:** 2026-07-09
**Status:** Fixed in Milestone 1 execution-safety work; generalized 2026-07-10

## Symptom

VirtualHID repair displayed an administrator password prompt even though the
privileged helper completed the repair. The flow also repeated equivalent VHID
repair and restart operations.

## Evidence and Timeline

The application log around 16:38:06-16:39:20 and
`/var/log/com.keypath.helper.stderr.log` showed this sequence:

1. `repairVHIDDaemonServices` started over the shared XPC connection.
2. A detached post-fix refresh called the helper `getVersion` health probe.
3. The helper processes requests serially, so the three-second version probe
   waited behind the mutation and timed out.
4. The version timeout cleared and invalidated the shared connection.
5. The helper completed the mutation, but its reply no longer reached the app.
6. The router treated the missing reply as definitive failure and invoked the
   AppleScript administrator fallback without first checking system state.
7. A later helper attempt produced the final successful state.

## Root Cause

`HelperManager` only logged concurrent calls; it did not serialize them.
`getHelperVersion()` had authority to invalidate the same connection used by a
mutation. The router also equated a transport outcome with an operation outcome
instead of using the existing authoritative VHID postcondition.

The UI amplified the race by mapping daemon misconfiguration, daemon-not-running,
and a final restart to the same repair recipe during one button action.

## Fix and Invariants

- All helper IPC is FIFO-serialized inside `HelperManager`; health probes wait
  for active mutations.
- A health-probe timeout never invalidates the shared connection.
- Helper mutation timeouts are represented as ambiguous because the helper may
  have completed after the reply path was lost.
- Every helper-first router operation with an administrator fallback verifies
  its operation-specific postcondition after any helper error. A satisfied
  postcondition returns success without fallback; an unsatisfied postcondition
  permits exactly one configured administrator fallback, followed by the same
  postcondition check.
- Uninstall rechecks filesystem and optional driver postconditions after a
  failed helper reply before offering or running Emergency Cleanup.
- `InstallerEngine.run` and `runSingleAction` share one transaction gate.
- The Karabiner page requests at most one equivalent VHID daemon repair per
  automatic repair action.

## Regression Coverage

- `HelperManagerTests.testHealthProbeWaitsForActiveHelperMutation`
- `HelperManagerTests.testPrivilegedHelperOperationsAcquireGateSerially`
- `PrivilegedOperationsRouterTests.testLostHelperReplyWithSatisfiedPostconditionSkipsFallback`
- `PrivilegedOperationsRouterTests.testFailedHelperWithUnsatisfiedPostconditionInvokesFallbackOnce`
- `PrivilegedOperationsRouterTests.testRuntimeRecoveryLostHelperReplyWithReadyRuntimeSkipsFallback`
- `PrivilegedOperationsRouterTests.testRuntimeRecoveryLostKillReplyWithStoppedRuntimeSkipsKillFallback`
- `PrivilegedOperationsRouterTests.testNewsyslogLostHelperReplyWithInstalledConfigSkipsFallback`
- `PrivilegedOperationsRouterTests.testDriverInstallLostHelperReplyWithInstalledDriverSkipsFallback`
- `PrivilegedOperationsRouterTests.testProcessTerminationLostHelperReplyWithExitedProcessSkipsFallback`
- `PrivilegedOperationsRouterTests.testKillAllLostHelperReplyWithStoppedRuntimeSkipsFallback`
- `UninstallCoordinatorTests.testLostHelperReplyWithSatisfiedPostconditionsSkipsEmergencyCleanup`

## Runtime Verification

After an uninstall and fresh app deployment on 2026-07-09, the installed helper
ran a real `repairVHIDDaemonServices` mutation from 19:22:46.416 through
19:23:00.519. The next `getVersion` probe did not begin until 19:23:01.472.
During that interval the logs contained no helper timeout, concurrent-XPC
warning, connection invalidation, AppleScript invocation, sudo fallback, or
administrator prompt. Installed-app verification then confirmed the KeyPath
process, helper, Kanata launchd job, Kanata process, and TCP readiness on
`127.0.0.1:37001`.

The incident does not justify snapshot convergence or Swift module extraction;
those remain later milestones after execution safety is verified.
