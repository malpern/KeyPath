# Recover keymap edits with their rule sources

Changing the logical keymap prepared a collection and regenerated configuration
through the legacy save path. A rejected reload could leave generated/source files
on the attempted layout while the in-memory keymap fields reverted.

Keymap changes now recover interrupted operations before preparing their candidate
and use the retained rule-state transaction. Rejection restores the exact config
and source files, then restores the manager's keymap fields and the matching
optimistic display preference before reporting the error. A newer display choice
is preserved. External-file conflicts retain the newer file and recovery journal.

The existing custom-rule conflict warning and pending-save policy are unchanged.
UserDefaults preferences still require durable crash recovery; this change only
makes their in-process rollback consistent with rule-source settlement.
