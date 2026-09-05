# Configuration save pipeline

KeyPath has two principal app configuration-write paths. Reload execution uses
the dispositions introduced by #732: `applied`, `pending`, `rejected`, and
`failed`. Propagation is currently uneven: `SaveCoordinator` preserves the reload
result, but collection regeneration still returns a Boolean and its runtime
callback discards the reload outcome. CLI apply/restore are separate paths.

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

The retained reload result describes the application attempt, not whether backup
restoration succeeded. File rollback/fallback still exists, but source stores,
preferences, and installed-pack records do not yet share one transaction.
See the [consolidation baseline](../planning/consolidation-baseline.md) for paths
and remaining gaps. UI presentation changes require discussion before implementation.

The removed `ConfigurationManager.writeGeneratedConfig`,
`writeValidatedConfig`, and legacy mapping-save methods had no production call
sites. They performed direct file writes outside the supported ownership model,
which could bypass current-configuration updates and rollback classification if
they were reused later.
