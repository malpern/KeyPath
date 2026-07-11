# Health indicator churn during startup

## Symptom

After launch, the overlay could show **Ready**, dismiss it, and show it again
several times. A TCP warning could also appear briefly before the system settled.

## Root causes

Three independent publication problems amplified normal health refreshes:

1. Every successful validation was rendered as a new healthy transition, even
   when the previous semantic state was already healthy.
2. The Settings status view observed `lastValidationDate` and responded by
   requesting another validation, creating a publication feedback loop.
3. Missing TCP configuration evidence was collapsed from `nil` (not captured)
   to `false` (known misconfiguration), allowing incomplete snapshots to render
   a warning.

Concurrent controller callers could also await the same validator capture and
then publish the shared result more than once.

## Fix and invariant

- Render **Ready** only when health transitions from unhealthy or unknown to
  healthy. Periodic healthy-to-healthy refreshes are silent.
- A view observing validation publication may copy published evidence, but must
  not request validation from that observation callback.
- Preserve optional health evidence. `nil` is inconclusive and must not be
  rendered as an explicit failure.
- Coalesce validation at the state-controller publication boundary, not only at
  the underlying snapshot capture boundary.

Tests cover stable healthy refreshes, unhealthy-to-healthy recovery, unknown and
explicitly false TCP evidence, concurrent refresh publication, and the Settings
observer invariant.
