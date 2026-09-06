# Collection and layer membership recovery

Collection addition used a persistence-only Boolean and a separate regeneration
to roll back. Removal and batch enable lacked manager rollback. Layer removal
wrote CustomRules.json before regeneration, so even a validation failure could
permanently delete rules while keeping the old configuration.

These entry points now recover interrupted state before snapshots and use the
same retained three-file transaction as custom-rule edits. A rejected reload
restores the exact original files before a compensating reload. Manager rollback
never regenerates over an external edit. Layer creation uses recovered data for
its duplicate check and respects the add operation's failure result.

Temporary-store tests exercise rejected add/remove/batch/create/delete, pending
layer deletion with one reload, external-edit preservation, and interrupted
recovery before a duplicate-layer early exit. This change does not alter conflict
or ownership decisions, or claim atomicity for leader preferences/managed packs.

Collection addition's Boolean now propagates through RuleCollectionsCoordinator,
RuntimeCoordinator and KanataViewModel. Both Karabiner import surfaces include
unsaved collections in their existing partial-import error instead of completing
or dismissing. Mapper creation selects the new layer only after a successful
save and refresh, and preserves navigation made while saving. This corrects
existing failure handling; no new status UI or import atomicity is introduced.
