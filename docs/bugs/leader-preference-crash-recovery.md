# Leader preference could outlive a rejected rule revision

The Leader Key collection updates both generated rule files and the
`KeyPath.LeaderKey.Preference` defaults value. Before this fix, the preference
was persisted before `ConfigurationService` created its retained rule journal.
A process exit in that interval could leave the next launch generating from the
new leader preference after the rule files recovered to their prior revision.

Leader candidates now remain local to `RuleCollectionsManager` while generation
and validation run. `RecoverableRuleWrite` version 2 journals the fixed leader
preference role beside the config and two source stores before writing any of
them. It synchronizes and verifies the canonical `com.keypath.KeyPath` defaults
domain before runtime application. Rejection, failure, cancellation, and startup
recovery restore the preference and files together. Version 1 journals still
decode with no preference entries.

The installed CLI prepares reconciliation as a local candidate too. A real
`config apply` journals that candidate with the generated config in the raw
config scope; a dry run only injects it into generation. Validation and file
failures therefore cannot advance the GUI defaults domain by themselves.

The synchronization barrier follows Foundation's documented process-exit contract:
it waits for in-progress defaults writes and the result is read back before reload.
It is not a claim of atomic persistence across sudden power loss.

Recovery accepts only the recorded before or after leader value. A third value
means another writer changed the same configuration input; recovery stops before
restoring any file and leaves the journal in place. Unrelated display preferences
are not journaled and are never restored by this operation.

Logical keymap persistence is not covered by this fix. The overlay currently
persists its selection before it calls the rule manager, so its true prior value
is unavailable at journal creation. That workflow requires moving persistence
behind transaction admission rather than inferring a preimage. Context HUD
timing/trigger settings, device selection, and the generated-file handwritten
ownership guard are also separate follow-ups.
