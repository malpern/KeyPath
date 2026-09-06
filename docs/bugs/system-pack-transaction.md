# Keep system-pack restore snapshots with the installation record

System packs wrote a standalone managed-collection snapshot, regenerated rules,
and then wrote the installation record. Interruption or metadata failure could
separate those states. Removal also committed restored rules before deleting its
record and snapshot, and retried some runtime failures as though they were mapping
conflicts.

New installations embed their managed-collection snapshot in the installed-pack
record. The record, snapshot, and three rule files participate in the existing
retained pack transaction. Rejection restores the exact previous revision. Removal
uses the embedded snapshot, falling back to standalone snapshots for older records.
Malformed restore data blocks mutation. Legacy snapshot cleanup follows successful
settlement; it is not needed to recover the authoritative revision.

The existing Restore Previous / Keep Current choice and managed-default confirmation
remain. The known conflict-disable retry is restricted to generation mapping
conflicts; a rejected runtime reload must not silently disable more collections.
Preferences, cross-instance cache freshness, and revision-aware watching remain open.
