# Keep collection-backed pack records with their rules

Collection-backed pack installation first committed its collection change, then
wrote the installed-pack record. A metadata failure needed a second rollback save;
a process interruption between writes could leave an enabled collection without an
installation record. Removal had the inverse gap.

The existing collection toggle now accepts the pack owner's prepared record change
and passes it to the canonical rule save. Configuration, collections, custom rules,
and installed-pack metadata remain in one retained journal through runtime
classification. Rejection restores the four-file revision before manager rollback.
Pack callers retain the full save result so metadata, permission, and recovery
failures keep their underlying cause rather than becoming a generic toggle failure.
External conflicts preserve the newer revision and journal rather than regenerating
over them. Existing ownership, prerequisite, conflict, and disable confirmations
are unchanged.

System packs and their managed-collection snapshots remain separate work. This does
not make preferences crash-atomic or change the pending-save policy.
