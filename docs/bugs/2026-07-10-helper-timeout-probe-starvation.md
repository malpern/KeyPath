# Helper timeout probe starvation

## Symptom

After an XPC mutation timed out or lost its reply, the follow-up helper health
probe could wait behind the abandoned mutation, clear a newer connection from a
late callback, or classify the helper as unhealthy before the XPC service had a
chance to recover. That could turn an ambiguous transport failure into an
incorrect repair decision.

## Root cause

The helper operation gate did not re-check cancellation after a queued waiter
acquired its permit. XPC proxy errors were also allowed to fall through to the
generic callback timeout, and connection invalidation handlers were not tied to
the connection generation that installed them.

## Fix

- Re-check cancellation immediately after acquiring the helper operation gate
  and release the permit before throwing.
- Normalize XPC interruption errors as ambiguous mutation outcomes and complete
  the request immediately when the proxy reports an error.
- Associate invalidation, interruption, and empty-version callbacks with a
  connection generation so stale callbacks cannot clear a replacement.
- Give a recently timed-out mutation a bounded recovery window before probing.
- Mark a probe in that recovery window as incomplete (`timedOut`) evidence in
  `SystemValidator`, rather than complete evidence that the helper is unhealthy.

## Regression coverage

`HelperManagerTests` covers cancellation-safe gate acquisition, XPC interruption
normalization, the bounded recovery window, and rejection of stale connection-end
callbacks. `SystemValidatorTests` covers conservative capture-status aggregation.
