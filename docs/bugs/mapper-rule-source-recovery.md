# Mapper rollback must restore rule sources

The mapper previously called `saveCustomRule(skipReload: true)`, committing the
configuration and both source stores before SaveCoordinator attempted a reload.
A rejected reload restored only keypath.kbd; subsequent regeneration could revive
the rejected rule from CustomRules.json. The caller's optimistic manager state
also retained the rejected rule.

The mapper now prepares the same conflict decision in memory and lets
SaveCoordinator retain the three-file transaction through reload. Failure restores
an exact receipt and the manager snapshot; compensating reload runs without
inheriting cancellation while admission remains held. No caller regeneration is
used for this rollback, because it could clobber an external edit. External
revision conflicts preserve the journal and report recovery failure.

ConfigurationRuleWriteTests cover stage/commit observer timing, exact rollback,
external changes, and interrupted recovery. SaveCoordinatorTests cover mapper
reload dispositions, source absence restoration, empty-file preservation, and
failed recovery. Collection/pack mutators are not yet migrated to this runtime
transaction; their compatibility Boolean continues to mean persisted.
