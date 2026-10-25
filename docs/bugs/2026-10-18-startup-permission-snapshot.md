# A successful start must not be validated with pre-runtime permissions

Every launch of the October 18 Air candidates (09:57 and 10:19 installs) logged
`Validation FAILED - 1 blocking issues` about 150 ms after `Session runtime
ready`, set the overlay health indicator to `unhealthy(1)` immediately after the
splash hid, and only reported success about 1.2 s later. The same launches logged
`Backend setup incomplete - auto-launching wizard`; its one-second re-check saw
`ready=true`, so the wizard itself did not open.

Cause: `PermissionOracle` caches a snapshot for 1.5 s. The launch snapshot was
sampled before the session worker existed, so the runtime's permissions were
`session-process-not-verified` and `System ready: false`. Validation after the
worker became ready was served that cached snapshot (age 1.013 s). The deeper
issue was that invalidation did not cover a computation already in flight: a
later caller coalesced onto it, and its stale result could overwrite a fresher
cache entry. `forceRefresh` had the same gap.

Fix: invalidation advances a cache generation, drops the in-flight task, and a
computation started before it is neither shared nor cached.
`ServiceLifecycleCoordinator` invalidates through `SystemStateProvider` when a
session runtime is verified ready, before it publishes the state change. This
covers ordinary launch and wake restarts. No timing, polling or UI debounce was
added; genuine permission failures still report immediately.

Regression coverage: `PermissionOracleInvalidationTests` holds a snapshot across
an invalidation and fails before the fix (the later caller joined the stale
computation). `SessionStartPermissionSnapshotTests` primes a pre-runtime
snapshot, starts a session, and fails before the fix (the cached snapshot was
reused). Absence of the brief launch indicator on the Air is manual acceptance.
