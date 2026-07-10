# Zero-Recipe Installer Run Reported Unverified Success

**Date:** 2026-07-10
**Status:** Fixed

## Symptom

An install or repair plan containing no recipes returned `success = true`
after capturing final state, even when that final snapshot was incomplete or
now required repair work. Consumers that trusted `InstallerReport.success`
could therefore disagree with the attached `finalContext`.

Two early-return paths also omitted correlation evidence that was already in
scope: `runSingleAction`'s no-recipe failure and CLI repair's user-action
result.

## Root Cause

Postcondition verification only considered declarations on executed recipes.
A zero-recipe plan had no declarations, so the empty verification set passed
vacuously. The final snapshot was attached for consumers but did not gate the
engine's own terminal result.

## Fix and Invariants

- Non-inspection zero-recipe runs re-plan from the fresh final context.
- Success requires complete final evidence and a second ready plan that still
  contains no recipes.
- Verified no-ops report the explicit `verified-no-op` completion state and
  successful verification telemetry.
- Incomplete or degraded final evidence reports `verification-failed` and
  includes a recovery plan when available.
- Early no-recipe and user-action results preserve plan and before-snapshot
  identifiers.

## Regression Coverage

- `InstallerEngineEndToEndTests.testExecuteRejectsNoOpWhenFreshFinalStateRequiresRepair`
- `InstallerEngineEndToEndTests.testExecuteRejectsNoOpWhenFreshFinalEvidenceIsIncomplete`
- `InstallerEngineTests.testExecuteRecordsStructuredRepairTelemetryForNoopPlan`
- `InstallerDecisionPipelineLintTests.testEarlyInstallerExitsPreserveCorrelationEvidence`
