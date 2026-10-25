# Pack metadata writes outside the installer

The Rules toggles wrote InstalledPackTracker directly. Pack detail also attempted
record repair with `try?` and then unconditionally displayed installed, even if
persistence failed. Repair read the view manager's cached collections, so a stale
view could recreate a record after another writer disabled the collection.

PackInstaller now owns both operations under configuration admission. Visual-only
toggles cannot install nonvisual packs; catalog installation retains its existing
pre-install gates. Repair recovers an interrupted rule journal before reading
persisted collections and refuses incomplete source reads. A failed record write
throws to the existing detail-view error area.

Keystroke History activation/clearing moves from UI closures to the successful
app-tracker operation, using the history service's own method. A separate CLI or
custom-directory tracker does not directly mutate the app singleton. Existing
notification-based recording updates remain unchanged. Rules toggle failures are
also tagged with request identities so an older failure cannot revert a newer
choice.

Tests use temporary source and tracker files: stale manager state, interrupted
rule writes, failed metadata persistence, corrupt metadata, trusted nested
admission, visual-only limits, and preserved catalog conflict checks. No new
ownership/conflict policy or full pack rollback is implied by this consolidation.

Deferred detail refreshes use detached MainActor tasks so notifications posted
inside a save do not carry its task-local lease into another mutation. They
queue normally, are cancelled on dismissal, and do not publish cancellation
errors or stale results. A test starts deferred repair while its notifying owner
holds admission and verifies that the record is created only after release.
