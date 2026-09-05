# Recoverable rule-file persistence

Collection regeneration prepares and validates the generated config and encodes
both source stores before replacing any file. `ConfigurationService.saveRuleState`
uses the existing store encoders, preserving the JSON formats and configured paths.
It publishes its configuration cache and observer callbacks only after the three
files have been committed.

The files are still replaced individually. This is recoverable persistence,
not a filesystem-wide atomic snapshot for arbitrary readers.

## Protocol

1. Take the directory's `.keypath-rule-write.lock` using `flock` off the main
   actor. Resolve any previous journal before starting another write.
2. Read prior bytes (including absence) for `config`, `collections`, and
   `customRules`. Record old and new bytes in `.keypath-rule-write.json` and sync
   the journal and its directory before replacing targets.
3. Replace and sync each target, verifying it still matches the recorded prior
   bytes immediately before replacement.
4. Mark and sync the journal as committed. Cleanup can be retried on startup if
   deleting the committed journal fails.
5. Publish the committed configuration and then notify rule observers/reload
   through the existing manager flow.

A write failure attempts restoration of the entire recorded prior set. If that
also fails, return both errors and keep the journal for a later recovery attempt.
Startup recovers the journal before the manager loads either rule store. Recovery
failure stops bootstrap and blocks subsequent journaled saves rather than
regenerating configuration from an ambiguous partial state.

A prepared journal restores old bytes; a committed journal only needs cleanup.
Recovery is idempotent and removes files whose prior state was absence. Journal
roles and recorded paths must match the caller's actual stores; the journal cannot
redirect recovery to arbitrary paths. Corrupt or mismatched journals fail closed.

## External changes and remaining boundaries

Recovery checks all targets before starting and checks each target again before
restoration. If a file matches neither the old nor the new bytes, it preserves
that external edit and leaves recovery unresolved. This is not a lock on editors
that do not cooperate with `flock`; a non-cooperating writer can still race the
last check and replacement. Watcher revision tracking and the shared application
operation remain necessary for the complete Phase 1 contract.

This slice covers persistence failure and interruption, not engine rejection.
Reload occurs after file commit under existing behavior. Preferences, installed
pack metadata, non-collection writers, and in-memory mutation ordering are not
included yet. Do not infer a successful live remap from a committed file set.
Cancellation is checked before journaled mutation; once mutation starts it
finishes commit or recovery rather than abandoning the write set midway.

Tests use temporary files to interrupt every write boundary, inject primary and
rollback failures, retain external edits, reject corrupt/misdirected journals,
verify bootstrap recovery, and assert observers see both source stores committed.
