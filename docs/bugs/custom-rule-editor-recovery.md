# Custom-rule editor recovery

Custom-rule save and toggle previously treated successful persistence as success
when reload was rejected. Removal and clear did not retain an in-memory snapshot.
Save/toggle fallback regenerated from a snapshot, which could overwrite unrelated
external edits after an earlier recovery conflict.

These four operations now prepare under the existing directory gate and call
SaveCoordinator.saveRuleState. The coordinator retains config and both source
stores through application/recovery. The manager restores only its in-memory
snapshot on failure and reports the original or recovery error. It no longer
writes a separate rollback revision. Interrupted journals recover before the next
editor snapshot, followed by a strict source reload when recovery changed disk.

The rollback review also found that refreshLayerIndicatorState called the runtime
layer-update method, which posts a TCP heartbeat. Local edits/recovery therefore
could be mistaken for runtime evidence. Display-only updates now use a separate
private setter; actual runtime observations keep heartbeat reporting.

Regression coverage checks save/toggle/remove/clear rejection, exact recovery
before the compensating reload, pending/skipped saves, preservation of external
source edits, interrupted-write recovery, and the heartbeat distinction.

Collection mutations, preferences, revision-aware watching, and UI status/state
presentation remain separate work. Manager arrays still follow the existing
optimistic preparation pattern; this is not isolation of every UI property read.

The pack tap/hold picker also recovers before locating and deriving the edited
rule. Its nested custom-rule save then uses the same transaction; this prevents
an interrupted write from hiding the target rule or supplying stale tap/hold data.
Validation cancellation remains silent, while other failed saves retain error
feedback through the manager's existing callback.

If file recovery succeeds but source decoding fails, the manager retains a pending
refresh requirement. Every later migrated editor/pack attempt must fully reload
both stores before preparing an edit. Merely removing the journal is not enough
to make stale arrays safe. The shared refresh helper clears that requirement only
after both stores load; tests verify repeated refusal and recovery after repair.

When a recovered journal may already have reached the engine, migrated manager
paths attempt an uncancelled coordinated reload before returning a snapshot.
This covers exits for missing rule IDs and cancelled conflict/provider prompts.
Rejected/failed recovery blocks the edit and remains required on the next attempt,
even after the file journal has been removed. Explicit headless callers with no
runtime callback retain their persistence-only contract; the manager retains the
runtime-refresh requirement if a callback is attached later.
