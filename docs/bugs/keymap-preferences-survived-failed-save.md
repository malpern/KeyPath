# Keymap preferences survived a failed save

A failed `setActiveKeymap` call restored only `activeKeymapId`. It had already
written the requested ID and punctuation flag to UserDefaults, left the new
punctuation flag in memory, and rebuilt the old collection using that new flag.
Rebuilding also discarded custom attributes of the prior keymap collection.

A temporary-directory write failure with isolated UserDefaults reproduced ten
assertion failures across stored and previously absent preference values. The
regression checks the ID, punctuation, exact prior collection, and preferences.

Preferences now persist only after config/source-store persistence completes.
Failure restores the previous punctuation option and the exact previous keymap
collection at its prior position, preserving unrelated collections. UserDefaults
is injectable for isolated tests; production still uses the existing standard
domain and keys. A pending engine reload remains a successful persisted edit.

The overlay also writes its display selection before calling the manager.
Failure restores that attempted display selection, and reverts a failed
punctuation toggle without replacing other layouts' remembered settings. The
comparison with the attempted selection preserves a newer display choice. The
overlay ignores a callback for the already-active selection so AppStorage's
rollback notification does not trigger a second save.

This fixes ordinary persistence-failure rollback. It does not make UserDefaults
and the file journal one crash-atomic transaction or serialize all collection
mutations; those remain part of the broader application-operation migration.
