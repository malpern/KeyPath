# Configuration save pipeline

KeyPath has two principal app configuration-write paths. Reload execution uses
the dispositions introduced by #732: `applied`, `pending`, `rejected`, and
`failed`. Propagation is currently uneven: `SaveCoordinator` preserves the reload
result. Collection persistence now retains that same `ReloadResult` through
its runtime callback, while its compatibility Boolean still means persistence
completed. CLI apply/restore also participate in directory admission; see below.

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

These describe the target ownership and save contract; complete multi-store
runtime recovery remains incomplete for global collection and pack operations.

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
For raw/generated saves, `SaveResult.recoveryResult` describes file recovery: `notAttempted`,
`restoredPreviousConfig`, `wroteMinimalSafeConfig(backupError:)`, or
`failed(backupError:fallbackError:)`. A minimal safe file is not restoration of
the prior revision. Both recovery errors are retained if neither write succeeds;
the original reload result and save error remain available. Applied/pending saves
and failures before a write report no recovery attempt. Staged rule/app edits cancelled before reload can still require file recovery.

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

Each service retains its FIFO queue. Services running as the same macOS user
and targeting the same configuration directory acquire a cooperative OS file lock, held through the admitted
operation. Cross-process ordering is exclusive but not globally FIFO. Callers
that compose trusted nested work still share the same service/permit owner. Direct service writers now acquire this gate too: collection/raw/repaired saves,
initial creation, backup/fallback and journal recovery. Public signatures remain
unchanged; trusted coordinator restoration and collection persistence forward
permits through internal overloads. Missing-file backup reads carry the permit
through self-healing creation so the backup retains stored rules. CLI operation
ownership is described below. App-specific edits and Simple Modifications now
use SaveCoordinator; startup app-include creation uses the same directory gate.
Source/cache freshness and external edits remain separate work. Merely using
this service for validation does not acquire write admission. Pack operations hold admission while staging
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

This is cooperation between migrated writers running as the same macOS user,
not protection against external editors or custom-directory writes from another
UID. Privileged helper callers do not use this gate. The gate alone does not
refresh cached app source state or coordinate unmigrated feature writers. Those
remaining changes are necessary before claiming whole-operation safety.

## CLI configuration ownership

`ConfigFacade.applyConfiguration` admits before loading collections/custom rules
and reconciling the leader preference, then retains admission through generation,
validation, save and the reload callback. The nested service save receives the
explicit permit. Dry-run generation also participates because it temporarily
reconciles a shared preference. The default loaders read the facade's requested
configuration directory rather than the singleton stores' default directory.

CLI backup and restore hold the same directory lease through copying and optional
reload. Backup is now an async API so lock contention does not block an actor;
the CLI command syntax and output are unchanged. A callback attempting another
apply, backup or restore is rejected before copying or staging preferences.

This does not yet change reload-result semantics, make directory restore atomic,
or include preference restoration in rejected-apply recovery. Feature-specific
writers remain separate migration work. Backups remain copies of current disk state; this scope does not recover pending journals
or refresh the app's cached state following a CLI restore.

## CLI pack ownership

`PacksFacade` admits install, uninstall and configure before inspecting installed
state. A facade manager factory constructs its dependencies only. Immediately
before an actual mutation, the admitted command reads the manager's collection
and custom-rule stores and hydrates the manager; dry-run and no-op paths skip
that source hydration. Nested installer calls receive the existing permit.

This closes the pre-admission source snapshot window for CLI pack mutations.
Some gallery/summary paths still write metadata directly. Writer consolidation
and whole-operation recovery remain necessary; the operation lease alone does
not solve those gaps.

### CLI command scope

`CLIConfigurationOperation.run` adapts the existing service gate to the CLI module.
Its scoped rule, collection, pack, and config facades carry an explicit active permit.
Commands compose source edits and optional `--apply` sequentially inside that scope;
batch ensure holds ownership across all its items. Scoped mutation after return is
rejected as an expired permit. A fresh facade in a callback still cannot reenter.
The scope is for sequential command composition, not concurrent child mutations.

Standalone rule and collection mutations also acquire directory admission before
loading their source stores. Read-modify-write operations therefore see the last
cooperating writer's committed data. Scoped stores and pack metadata resolve from
the command's configuration directory. Default standalone stores preserve their
existing test isolation. This is ownership, not rollback: failed apply retains the
existing persistence behavior until the whole-operation recovery work is complete.

Installed-pack queries refresh from the current file; only an unreadable file
falls back to the last successfully read/persisted snapshot. A missing file clears
that fallback. Mutations read strictly and persist before notification; malformed metadata
is preserved with an error. Pack operations hold directory ownership around those
reads and writes. Direct UI metadata writers still need consolidation under the
same operation boundary; the tracker actor alone is not a cross-process lock.

Pack install/uninstall/configure and CLI collection ownership decisions perform a
strict metadata read under admission before staging source edits. Display-only
fallback state is never sufficient to authorize these mutations. Each CLI command
retains one tracker instance for its scope.

## App-specific and Simple Modifications edits

App-specific edits use a three-file staged journal through runtime classification:
AppKeymaps.json, keypath-apps.kbd and keypath.kbd. Applied/pending commits publish
the cache; rejection/failure/cancellation rolls back the prior file set and attempts
a compensating reload. Recovery refuses to overwrite an external revision. The
recovery result retains the compensating reload outcome. App-context refresh runs
under admission after immediate or deferred application, including recovery.

App edits require the main/include pair to be reproducible from stored rules.
Hand-written or divergent content remains untouched with an editing-limit error;
explicit backed-up conversion is separate future work. Startup include creation
also preserves existing differing content.

SimpleModsService calls RuntimeCoordinator.editConfiguration, which delegates to
SaveCoordinator.editConfiguration. Admission precedes file capture and a pure
SimpleModsWriter transform. Validation checks the proposed content; the captured
revision is compared again before writing. The editor's loaded revision must also
match, preventing stale editor state from overwriting an external edit. Debounced
edits retain a settlement chain even when queued work is cancelled.

Simple Modifications retains the complete SaveResult, including pending reloads,
and reloads editor state after a failed save. It uses existing raw-file rollback;
it does not yet provide the app-specific journal or compensating reload. The old
opt-in smoke test that mutated the user's real file without restoration is replaced
by temporary-directory save/reload tests. Physical engine acceptance remains a
separate installed-app QA obligation.

## Pack metadata ownership

Rules visual-only toggles now use PackInstaller.setVisualPackEnabled. It admits
before strict tracker reads, preserves existing quick settings unless supplied,
and commits the record before settling the app's visual capability. Catalog
install still runs its existing dependency/conflict gates first; this internal
consolidation does not standardize the two entry points' product policy.

Pack detail's missing-record repair uses PackInstaller.reconcileInstallRecord.
It reads persisted collection state after admission, refuses incomplete reads,
and propagates persistence failure instead of reporting installed unconditionally.
It preserves the existing backfill policy; it does not decide new pack ownership.

## Mapper rule-state recovery

`SaveCoordinator.saveMapping` uses the manager's conflict resolution and in-memory
rule preparation, then retains the configuration and both source stores in one
journal until reload classification. Applied/pending commits; rejected, failed,
or cancelled application restores the exact previous files (including absence or
an empty file), then attempts a compensating reload if application was attempted.
The result keeps the original reload and a separate `restoredPreviousRuleState`
recovery reload, or `ruleStateRecoveryFailed`. Restoring files does not imply
that the recovery reload succeeded.

Only a committed revision notifies configuration/collection observers. On failure,
the manager's optimistic snapshot is restored without generating or writing again.
External edits after staging stop commit and rollback, preserving the files and
journal for attention. The staged writer also compares the captured pre-validation
revision before writing. SaveCoordinator's unused engine-client dependency is
removed; runtime work continues through the injected reload callback.

Other collection mutators still use their existing immediate-commit compatibility
path. Their snapshot regeneration, pack-wide preferences/metadata recovery,
stale manager caches, revision-aware watching, and raw-file runtime recovery
remain separate migrations. This mapper change does not claim those are complete.

## Custom-rule pack installation

PackInstaller prepares all custom-rule bindings in memory, then invokes the same
SaveCoordinator rule operation with an installed-record change. ConfigurationService
stages the config, collections, custom rules, and installed metadata under the
`.packRules` journal scope. Both configuration and tracker observers are notified
after commit. Failed preparation makes no file changes; failed apply or persistence
restores the prior revision, preserving external edits if restoration conflicts.
The old per-binding persistence loop and pack-ID-based partial cleanup are removed.

Rule startup recovery resolves the installed-packs.json path from the configuration
directory by default. Tests or integrations using a nonstandard metadata path must
supply their tracker explicitly to recovery, just as custom rule stores must be
supplied; journal contents cannot select restoration targets. System packs,
collection-backed packs, settings updates, removal, and pack collection snapshots
still have their existing separate commit boundaries.

Custom-rule pack removal and quick-setting updates now use that same retained
pack transaction. Record changes can upsert or remove one pack while preserving
other records. Preparation performs no per-binding writes; notifications follow
commit. Settings that affect a collection, such as Home Row Mods timing, restore
the collection and stored setting together after rejected application. Metadata-only
operations still skip config generation and runtime reload.

## Custom-rule editor mutations

The manager's save, toggle, remove, and clear custom-rule operations now prepare
under admission and use SaveCoordinator's retained rule transaction. They recover
interrupted source writes before capturing the next in-memory snapshot. Rejected
application restores the prior files/runtime and manager state; the manager does
not regenerate a second rollback over externally changed files. Existing conflict
and provider-disable choices remain in place. Explicitly skipped/absent reloads
still mean persistence without an application result.

Local layer-label refreshes do not emit TCP heartbeat notifications. Only an
observed runtime layer update supplies that evidence, including unchanged layers.

### Collection and layer membership

`RuleCollectionsManager.commitRuleMutation` is the shared settlement path for
custom rules and collection add/update, removal, batch enable, and layer removal.
It calls `SaveCoordinator.saveRuleState` and restores only the manager snapshot on
failure. Do not save CustomRules.json separately before deleting a layer: the
journal must capture both source stores before either changes.

Layer creation recovers interrupted state before its duplicate check, then calls
`addCollection` under the same permit. `addCollection` returns whether the save
committed (applied, pending, or explicitly headless); creation logs completion only
on success. Existing membership/conflict policy is unchanged. Leader preference
writes and other collection mutators remain separate migration work.

Collection addition's Boolean now propagates through RuleCollectionsCoordinator,
RuntimeCoordinator and KanataViewModel. Both Karabiner import surfaces include
unsaved collections in their existing partial-import error instead of completing
or dismissing. Mapper creation selects the new layer only after a successful
save and refresh, and preserves navigation made while saving. This corrects
existing failure handling; no new status UI or import atomicity is introduced.

### Collection settings and prerequisites

Simple collection setting edits use `updateCollectionSettings` to recover before
reading the candidate, preserve each editor's enable policy, and settle through
`commitRuleMutation`. A `true` return still means newly enabled and committed;
it does not independently assert application. Auto Shift and repeat edits keep
existing disabled collections disabled; catalog fallback is enabled as before.

Prerequisite-aware callers recover before deriving their candidate. Their common
apply helper then keeps the candidate and confirmed providers in one retained
transaction, with no separate snapshot-regeneration rollback. Explicit skipReload
still means persistence-only for higher-level callers. These changes do not
include leader preferences or alter prerequisite/conflict choices.

### Collection toggles, replacement, and leader edits

These public mutations now take recovered snapshots before any candidate changes
and settle through `commitRuleMutation`. Single-output editing handles the leader
preference/activators in the same operation, rather than calling another save
after changing the selected output. Replace-all snapshots the original arrays.

The commit helper optionally receives the prior leader preference. On failure it
restores that preference before error feedback only if it still equals the prepared
value; a newer value is preserved and reported. This is in-process preference
rollback only. UserDefaults is not yet part of the crash-recovery journal.

Interrupted-save runtime admission is owned by `ConfigurationService`. Recovering
rule or app journals marks a runtime refresh requirement; editor callbacks cannot
run until the existing reload owner accepts or defers that refresh. Failure retains
the requirement for later owners sharing the service, even after journal removal.
Rule-source recovery also advances a revision observed by the manager so recovery
through an app/raw editor cannot leave that manager's arrays stale. This state is
in-process and does not replace durable raw-save or cross-process cache recovery.

Raw/generated saves retain a `rawConfig` journal for the main file through engine
classification. They restore exact bytes and recover runtime on rejection, preserve
external conflicts, and invalidate the parsed cache only after settlement. Accepted
raw revisions still settle under caller cancellation. Explicit restore keeps its
separate fallback path; ordinary save rollback does not replace an empty original
with generated content. Raw journal recovery participates in editor admission and
startup recovery without marking unchanged rule source arrays as stale.

A restored raw original that fails validation may be replaced by a separately
validated raw edit after recovery reload fails. Only an accepted replacement
clears that recovery requirement; cancellation, invalid candidates, and journal
conflicts never silently clear it.

Logical keymap changes use the same retained rule-state transaction as collection
edits. The manager recovers before candidate preparation and restores its layout
fields plus the matching optimistic display preference on failure. Persistent
keymap preferences update only after accepted settlement; they are not yet part
of the durable file journal.

Collection-backed pack install/removal passes its record change through the existing
collection toggle into the canonical rule save. The pack record and three rule files
share the retained pack journal and runtime settlement; there is no second metadata
write or fallback regeneration. System packs retain a separate path until their
managed snapshots join the transaction.

The collection toggle and rule-mutation settlement expose the canonical SaveResult
for callers that need its cause and recovery outcome. Existing Boolean editor APIs
adapt that result; pack callers retain it so metadata failures remain actionable.
