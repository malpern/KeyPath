# Collection toggle and leader recovery

Collection toggles and leader/output edits treated persistence as success and
regenerated a second revision on failure. Replace-all took its collection snapshot
after replacement. The leader picker changed its selected output before invoking
a nested leader save, so that nested snapshot already contained the proposed value.

These operations now recover before reading state and keep the original snapshot
through SaveCoordinator settlement. Replace-all snapshots before replacement. The
leader picker prepares its selection and activators in one operation instead of
delegating after a partial mutation. File/runtime rollback never regenerates a
new snapshot over an external edit.

If an operation changes the leader preference, the manager restores its prior
value before reporting an ordinary save failure, but only if the current preference
still matches the prepared value. A newer preference is preserved and named in
the error. Existing conflict/ownership/disable decisions and the broad explicit
leader-activator rewrite are unchanged.

**Remaining boundary:** preferences are still stored in UserDefaults outside the
durable file journal. This provides in-process rollback, not crash-atomic preference
recovery. Managed-pack snapshots, keymap preferences, and external-write watching
also remain separate work.

Tests cover rejected toggles, direct/picker leader edits, collection replacement
with and without reconciliation, pending commits, exact file restoration before
recovery reload, preference restoration before feedback, and preservation of a
newer preference.

The Rules and catalog single-key pickers clear their optimistic selection after
settlement and show the current model value, including after rejection. Edit IDs
prevent an older completion from clearing a newer pending choice. A catalog edit
also stops if its prerequisite pack installation did not succeed.
