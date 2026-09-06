# Custom-rule pack installs need one durable revision

Installing a pack with several bindings called `saveCustomRule` for each binding.
`skipReload` suppressed only the engine callback: each call still generated and
persisted files. A later conflict or failure could leave earlier bindings written.
The best-effort cleanup removed rules by pack ID, which could also remove rules
that existed before a reinstall attempt. The installed record was a later write,
and runtime rejection did not roll back the source files.

Custom-rule installs now prepare every binding using the existing conflict logic
before any persistence. SaveCoordinator stages the generated config, both source
stores, and installed-packs.json in a single `.packRules` journal. Applied or
pending runtime outcomes commit. Rejection, failure, cancellation, and metadata
write failures recover the entire prior revision; compensating reload runs only
when runtime application was attempted and file recovery succeeded. External
changes stop recovery without overwriting any member of the file set.

Startup rule recovery also recognizes the pack journal before loading sources.
Nonstandard injected metadata paths require the same tracker to be supplied for
recovery; journal contents cannot redirect restoration to arbitrary paths.

Only committed revisions publish configuration and installed-pack notifications.
Explicitly skipped or absent reload callbacks remain absent outcomes, not an
invented applied status. System/collection-backed packs, removal, quick-setting
updates, and preference/snapshot recovery remain separate migrations.

During validation, the existing system-pack tests were found writing modern and
legacy uninstall snapshots under the real user configuration directory. Both
snapshot paths now resolve through AppPaths.configDirectory, whose per-process
test sandbox preserves production paths. The tests use those same resolved paths.
The managed-apply failure fixtures now fail a source read after admission rather
than blocking admission itself, retaining their snapshot rollback coverage.

Recovery also refreshes the admitted pack manager from the restored source stores
before preparing another mutation. CLI pack commands recover before installed-state
shortcuts, so an interrupted installation cannot be reported as already installed.

## Removal and quick-setting mutations

Custom-rule removal now stages all owned-rule removals and deletion of the
installation record in the same transaction. It reloads once after preparation,
not once per removed rule. Metadata write failure and runtime rejection restore
the complete prior revision, including the installed record. The existing
pack-tag ownership/removal policy is unchanged.

Quick-setting changes stage the updated collection timing or replacement custom
rules with the new setting values. A rejected timing update restores the old
collection and metadata together. Metadata-only settings and cleanup of a pack
with no tagged rules still avoid generating or reloading configuration.

System-pack install/removal, collection-backed install/removal, and tap/hold
picker edits remain separate migrations. This change does not include preference
or managed-snapshot recovery or change the catalog's conflict/ownership policy.

Timing settings reject a missing collection or incompatible configuration before
writing the installed record. Such a target is not a metadata-only setting; treating
it as one would claim the new timing while leaving the rules unchanged.
