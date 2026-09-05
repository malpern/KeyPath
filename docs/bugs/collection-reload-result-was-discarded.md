# Collection reload result was discarded

The runtime callback for `RuleCollectionsManager.onRulesChanged` awaited
`applyPersistedRuleChanges()` but discarded its `ReloadResult`. The manager then
returned true after any completed callback, including rejection or failure.

The callback now returns that same application result. `persistRules()` retains
it alongside completed persistence, or returns the persistence error without
calling reload. Missing/skipped callbacks produce nil instead of inventing an
applied or pending result. Conflict-resolution recursion retains the final retry
result and keeps its existing persistence-based rollback decision.

The old Boolean adapter intentionally continues to mean persistence completed.
Several callers respond to false by restoring only in-memory snapshots or
preferences; switching them to false after a persisted-but-rejected reload would
introduce disagreement with disk. Migrate these callers with multi-store recovery,
not by relabelling their existing Boolean. UI, sounds, notifications, and current
recovery behavior are unchanged by this contract step.

Temporary-store tests cover all four reload dispositions, exactly one reload,
persistence before callback, absent/skipped callbacks, filesystem failure before
reload, conflict retry, and compatibility Boolean semantics.
