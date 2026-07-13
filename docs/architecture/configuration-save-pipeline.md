# Configuration save pipeline

KeyPath has two supported configuration-write paths. Both preserve the reload
dispositions introduced by #732: `applied`, `pending`, `rejected`, and `failed`.

| Responsibility | Owner | Notes |
| --- | --- | --- |
| Generate and validate collection-backed configuration | `ConfigurationService` | `saveConfiguration` validates before its atomic write and updates the in-memory configuration and observers. |
| Coordinate generated/raw configuration saves | `SaveCoordinator` | Suppresses the watcher, validates, snapshots the last good file, writes, classifies reload, and rolls the file back after rejection or failure. |
| Persist rule and custom-rule source data | `RuleCollectionsManager` | Mutates the source stores before asking `ConfigurationService` to regenerate the file. |
| Reload the running engine | `ConfigReloadCoordinator` | Produces the four reload dispositions; `pending` means the write succeeded but the runtime is unavailable. |
| Handle external file edits | `ConfigHotReloadService` | Validates and reloads changes that were not suppressed as internal writes. |
| Create durable pre-edit backups | `ConfigBackupManager` | Used by explicit backup/recovery flows, not as an alternate writer. |
| Startup validation and editor/file utilities | `ConfigurationManager` | Does not own a save or raw-write pipeline. |

## Invariants

- Validate generated content before replacing the active file.
- Suppress the file watcher before an internal write to avoid a second reload.
- Treat `applied` and `pending` as successful writes.
- Restore the last known-good file after `rejected` or `failed`.
- Keep `ConfigurationService` as the only collection-generation writer and
  `SaveCoordinator` as the only generated/raw-save coordinator.

The removed `ConfigurationManager.writeGeneratedConfig`,
`writeValidatedConfig`, and legacy mapping-save methods had no production call
sites. They performed direct file writes outside the supported ownership model,
which could bypass current-configuration updates and rollback classification if
they were reused later.
