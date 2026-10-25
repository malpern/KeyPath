# Overlapping saves could roll back a newer edit

## Reproduction

A deterministic SaveCoordinator test holds the first generated save in its reload
callback, starts a second save, then rejects the first. Before the fix the second
save entered the pipeline and wrote its file while the first was suspended. The
first operation's rollback then replaced that later edit. The test failed on the
second `.saving` notification, the file while reload was suspended, and the final
file after both operations returned.

`@MainActor` protects synchronous access, but does not make an async method a
transaction. Both save APIs await configuration work and the reload callback.
They also used one mutable `lastGoodConfig` and the service's parsed cache as the
source for backups. Generated saves write raw content without updating that cache,
so even sequential edits could back up an older revision.

## Fix and boundaries

The existing coordinator now admits mapping saves, generated saves, and explicit
file restoration through one FIFO operation gate. Ownership spans validation,
write, reload, and recovery. Internal recovery does not reacquire the gate. A task-local operation token rejects recursive saves or restoration from a reload
callback with an explicit error, rather than queuing behind itself. Tokens rotate
at completion so inherited context cannot reject a later independent operation.

Each save reads its own pre-edit file snapshot and uses that value for recovery;
changing the public fallback backup cannot change an in-flight operation's
snapshot. An unreadable existing file fails before the edit. Missing-file behavior
continues through ConfigurationService's existing initialization path.

Already-cancelled requests never enter the gate. A queued cancellation is checked
when its turn arrives and releases the slot without writing, reloading, or changing
the active operation's status. Cancellation is checked again before mutation.
After mutation starts, the operation finishes reload/recovery rather than adding
an abandonment path that would leave partially applied state.

This is a prerequisite for the broader transaction migration, not a claim that all
configuration writes are now serialized. Direct collection/pack/CLI mutations,
external edits, source-store recovery, durable interruption recovery, runtime
reapplication of restored content, and stale presentation status timers remain
outside this coordinator-local change. Reload rejection still restores only the
file; the existing fallback behavior is unchanged. No UI or format changes.

## Verification

SaveCoordinator tests cover generated/generated overlap, generated/mapping overlap,
queued cancellation followed by another successful save, recursive reload save/restoration rejection, and restoration of the
latest file despite stale parsed cache or a changed shared fallback backup. The
existing four-disposition result and file-restoration tests remain in place.
