# Incomplete Installer Probes Reported Complete

**Date:** 2026-07-10
**Status:** Fixed

## Symptom

A failed process-conflict probe produced an empty, auto-resolvable conflict
result while the enclosing system snapshot remained `complete`. Installer
planning and postcondition verification could therefore interpret missing
evidence as proof that no conflicts existed.

Separately, a caller requesting a fresh snapshot could still receive component
installation facts from a private 15-second cache. The snapshot timestamp was
fresh, but some of its evidence was not.

## Root Cause

The conflict probe converted errors into a healthy-looking value without
propagating capture completeness. The freshness policy only governed the
canonical snapshot cache; it did not invalidate the subordinate component-fact
cache.

## Fix and Invariants

- Conflict capture now returns both evidence and capture status.
- A failed conflict probe yields fail-safe conflict evidence and marks the
  enclosing snapshot `failed`, so it cannot satisfy installer state or
  postcondition predicates.
- `.fresh` invalidates all validator-owned evidence caches before capture,
  including component facts and service-health evidence.
- Cached component facts use the same 1.5-second window as the canonical
  snapshot instead of defining a second 15-second freshness tier.
- Incomplete capture has explicit user-facing guidance to retry the status
  check before system mutation.

## Regression Coverage

- `SystemValidatorTests.failedConflictProbeIsIncomplete`
- `SystemValidatorTests.cachedCaptureReusesRecentSnapshot`
- `SnapshotConsumerLintTests.testFreshCaptureInvalidatesComponentFacts`
- `WizardPureLogicTests.test_failedCaptureProducesIncompleteStatusIssue`
