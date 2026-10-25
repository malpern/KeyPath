# Save recovery outcome was discarded

## Evidence

`SaveCoordinator` used to catch and log backup restoration errors in both mapping
and generated saves, then return only the original reload error. Its restoration
helper also returned normally after writing a minimal safe configuration. Callers
could not distinguish restoration of the previous file, replacement with a safe
fallback, or complete recovery failure.

Temporary-directory tests exercise both save APIs. An empty prior file triggers
restoration validation failure after writing the backup, followed by a successful
minimal fallback. Replacing the test config directory with a regular file during
the reload callback makes both recovery writes fail. No live service or user
configuration is used to inject these failures.

## Change

`SaveResult.recoveryResult` carries a separate file-recovery outcome. Failed
fallback retains both the backup error and the fallback error; the original
reload disposition and error are preserved. Missing backup and failed backup
restoration are distinct. Existing explicit-restore callers still receive a
thrown error if fallback fails, and can now inspect successful fallback results.

The save remains unsuccessful even when file recovery succeeds. The operation
gate releases after all recovery outcomes, so a failed recovery cannot prevent
the next save. Recovery adds no engine reload.

## Boundary

This is an internal result-contract step in Phase 1, not a complete transaction.
Source stores, preferences, pack records, runtime reapplication and durable crash
recovery remain separate work. Existing status presentation is unchanged; a
material UI treatment of recovery requires product discussion first. In
particular, a restored file is not proof of an operational keyboard engine.

Explicit-restore failure throws `SaveRecoveryError`, retaining both causes while
preserving the fallback error description used by existing presentation.
