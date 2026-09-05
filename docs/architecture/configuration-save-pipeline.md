# Configuration save pipeline

KeyPath has two principal app configuration-write paths. Reload execution uses
the dispositions introduced by #732: `applied`, `pending`, `rejected`, and
`failed`. Propagation is currently uneven: `SaveCoordinator` preserves the reload
result. Collection persistence now retains that same `ReloadResult` through
its runtime callback, while its compatibility Boolean still means persistence
completed. CLI apply/restore remain separate paths.

| Responsibility | Owner | Notes |
| --- | --- | --- |
| Generate and validate collection-backed configuration | `ConfigurationService` | `saveConfiguration` validates before its atomic write and updates the in-memory configuration and observers. |
| Coordinate generated/raw configuration saves | `SaveCoordinator` | Suppresses the watcher, validates, snapshots the last good file, writes, classifies reload, and rolls the file back after rejection or failure. |
| Persist rule and custom-rule source data | `RuleCollectionsManager` | Mutates in-memory state and requests a recoverable config/source-store write from `ConfigurationService`. Notifications follow the file-set commit and precede reload. Runtime rollback and preferences remain separate. |
| Reload the running engine | `ConfigReloadCoordinator` | Produces the four reload dispositions; `pending` means the write succeeded but the runtime is unavailable. |
| Handle external file edits | `ConfigHotReloadService` | Validates and reloads changes that were not suppressed as internal writes. |
| Create durable pre-edit backups | `ConfigBackupManager` | Used by explicit backup/recovery flows, not as an alternate writer. |
| Startup validation and editor/file utilities | `ConfigurationManager` | Does not own a save or raw-write pipeline. |

## Invariants

These describe the target ownership and save contract; collection and CLI paths
still need migration to enforce the same reload/recovery behavior end to end.

- Validate generated content before replacing the active file.
- Suppress the file watcher before an internal write to avoid a second reload.
- Treat `applied` and `pending` as successful writes.
- Restore the last known-good file after `rejected` or `failed`.
- Keep `ConfigurationService` as the only collection-generation writer and
  `SaveCoordinator` as the only generated/raw-save coordinator.

## Save result boundary

`SaveCoordinator` returns the original `ReloadResult` in `SaveResult.reloadResult`
after an attempted reload, for mapping and generated saves. A nil value means
the operation failed before that attempt. Existing `success` consumers retain
their behavior: applied and pending are successful saves. `success` alone does
not mean the runtime applied the configuration.

The retained reload result describes the application attempt. The separate
`SaveResult.recoveryResult` describes file recovery: `notAttempted`,
`restoredPreviousConfig`, `wroteMinimalSafeConfig(backupError:)`, or
`failed(backupError:fallbackError:)`. A minimal safe file is not restoration of
the prior revision. Both recovery errors are retained if neither write succeeds;
the original reload result and save error remain available. Applied/pending saves
and failures before reload report no recovery attempt.

Explicit restoration returns the same successful recovery outcomes and retains
its throwing contract when even the fallback cannot be written. These outcomes
assert only file recovery, not a second engine reload or a multi-store rollback.
Existing presentation and Boolean success semantics are unchanged.

File rollback/fallback still exists, but source stores,
preferences, and installed-pack records do not yet share one transaction.
See the [consolidation baseline](../planning/consolidation-baseline.md) for paths
and remaining gaps. UI presentation changes require discussion before implementation.

The removed `ConfigurationManager.writeGeneratedConfig`,
`writeValidatedConfig`, and legacy mapping-save methods had no production call
sites. They performed direct file writes outside the supported ownership model,
which could bypass current-configuration updates and rollback classification if
they were reused later.

## Shared operation admission

`ConfigurationService.operationGate` provides FIFO admission for generated and
mapping saves, explicit restoration, and the collection manager's public async
mutation APIs (including keymap selection), bootstrap reconciliation, and pack
install/uninstall/settings operations. Standalone regeneration, persistence,
prerequisite application, conflict retries and snapshot restoration also acquire
admission; their trusted nested callers pass the active permit. Admission happens before staging
in-memory collection state and remains held through persistence, reload and
recovery. Two coordinators using the same service share that admission queue.
Each save snapshots the file itself rather than using the parsed cache or a
mutable backup captured by another save.

Trusted nested calls pass the active permit explicitly: mapping saves enter the
custom-rule API, and collection helpers can enter another public mutation without
waiting on themselves. Callbacks receive no permit; recursive saves through the
same service fail instead of deadlocking. Permits expire with their operation.
Queued cancellation is observed at admission before mutation. Once admitted,
existing completion/recovery behavior remains unchanged.

Each service retains its FIFO queue. Services targeting the same configuration
directory also acquire a cooperative OS file lock, held through the admitted
operation. Cross-process ordering is exclusive but not globally FIFO. Callers
that compose trusted nested work still share the same service/permit owner. Direct service writers now acquire this gate too: collection/raw/repaired saves,
initial creation, backup/fallback and journal recovery. Public signatures remain
unchanged; trusted coordinator restoration and collection persistence forward
permits through internal overloads. Missing-file backup reads carry the permit
through self-healing creation so the backup retains stored rules. CLI operation
ownership, source/cache freshness, external edits and feature-specific writers
(such as SimpleModsService and AppConfigGenerator include-file saves) still need
migration. Those callers using this service only for validation do not acquire
write admission merely by validating. Pack operations hold admission while staging
arrays, making nested collection calls, updating metadata and running their
existing recovery paths; their multiple writes are still separate durable commits.
The collection journal below provides a separate durable file recovery boundary;
admission alone does not restore source stores or preferences after engine
rejection. See [the original coordinator race](../bugs/save-coordinator-overlapping-rollback.md)
and [shared mutation admission](../bugs/shared-configuration-admission.md).

Explicit-restore failure throws `SaveRecoveryError`, retaining both causes while
preserving the fallback error description used by existing presentation.

## Collection persistence boundary

`RuleCollectionsManager.persistRules()` returns `RulePersistenceResult`: either
`persisted(reloadResult:)` after configuration and both source-store writes, or
`failed(Error)`. The callback returns the original `ReloadResult`; applied,
pending, rejected, and failed remain distinct. Nil means the callback was absent
or intentionally skipped. Conflict-resolution retries carry the final result
back to the original caller without another reload.

`regenerateConfigFromCollections()` remains a compatibility adapter returning
`didPersist`. Do not reinterpret its Boolean as live application: callers perform
their own partial rollback on false, so changing it on reload rejection before
migrating multi-store recovery would create inconsistent state. Notifications follow the file-set commit; recovery from a partial store write is
provided by the journal below, separately from runtime rejection recovery.

Collection file persistence now uses [recoverable rule writes](recoverable-rule-writes.md).
It journals the generated file and both source stores, recovers before bootstrap
loads them, and defers configuration observers until the file set commits. This
does not yet change the collection Boolean's persistence-only meaning or couple
engine rejection to source-store recovery.

## Directory lease

The gate opens a persistent SHA-256-named sentinel under the current user’s
`Library/Application Support/KeyPath/ConfigurationLocks`. The key is the canonical
configuration path, folded on case-insensitive volumes. This avoids requiring a
writable configuration parent and survives replacement of the configuration directory.
Do not unlink the sentinel after an operation: existing waiters may already hold
handles to it. Its presence alone does not mean an operation is running.

Path inspection, sentinel creation and opening run on a utility dispatch queue.
`flock(LOCK_EX | LOCK_NB)` retries asynchronously and observes cancellation while
waiting; it never blocks the main actor or the serial file-I/O queue. As with the
service FIFO, a hung owner can keep a caller waiting until cancellation or release. The handle
is close-on-exec and released after completion or failure; process exit releases
the OS lock. File identity detects recursive callbacks through another service
or a directory alias. Inherited contexts carry a lease that becomes inactive
on release, allowing a child that outlives its operation to write later.

This is cooperation between migrated writers, not protection against external
editors. It also does not refresh cached source/pack state or hold admission over
CLI work performed outside service calls. Those remaining ownership/freshness
changes are necessary before claiming whole-operation cross-process safety.
