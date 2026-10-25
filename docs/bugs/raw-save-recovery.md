# Retained recovery for raw configuration saves

Raw/generated saves used an in-memory backup and restored only the main file after
an engine rejection. They neither retained a crash journal nor reloaded the restored
revision. Recovery could overwrite a newer external edit and could replace an empty
original with a generated fallback while the editor still reported rollback.

Raw saves now retain a config-only journal through reload classification. Applied
and pending revisions commit; rejection restores the exact previous bytes and uses
the existing reload owner to recover runtime before returning. A failed recovery
remains required in ConfigurationService for the next editor. External conflicts
preserve the external file and journal instead of regenerating a fallback over it.
A raw corrective edit may proceed when the restored original fails validation and
cannot reload. Its replacement must independently validate and receive an accepted
reload before the old recovery requirement clears. Invalid or cancelled corrective
edits keep the recovery failure visible; journal conflicts still block all edits.
Other source/sidecar files are not part of a raw edit. Existing first-run config
initialization still precedes the captured backup when the main file is absent.

Startup backup capture, explicit restore, and subsequent rule/app/raw editors recover the raw journal through the
shared configuration owner. Raw-only recovery does not imply that rule source
arrays changed. Explicit restore retains its separate fallback behavior; ordinary
failed saves no longer take that path. Accepted raw saves still settle when a newer
editor task has cancelled the original caller, preserving the existing contract.

This does not make preferences or managed-pack snapshots crash-atomic and does not
solve cross-instance/process cache freshness or revision-aware file watching.
