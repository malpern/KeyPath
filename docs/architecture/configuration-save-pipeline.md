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
| Persist rule and custom-rule source data | `RuleCollectionsManager` | Mutates in-memory state, generates/validates/writes config, then persists collection and custom-rule stores. Notifications precede its reload callback. These are separate writes, not an atomic multi-store transaction. |
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

## Coordinator-local operation isolation

Mapping saves, generated saves, and explicit backup restoration now share a FIFO
admission gate in `SaveCoordinator`. The slot is held across async reload and file
recovery. Each save snapshots the file itself; it does not use the possibly stale
parsed cache or read a mutable shared backup at rollback time. Queued cancellation
is observed at admission without a write or reload; after mutation begins the
existing completion/recovery path runs to completion.

This gate covers this coordinator only. Collection/pack/CLI writers, source-store
transactions, external edits, and durable crash recovery still need migration.
See [the reproduced rollback race](../bugs/save-coordinator-overlapping-rollback.md).

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
migrating multi-store recovery would create inconsistent state. This stage does
not change notification timing or claim recovery after a partial store write.
