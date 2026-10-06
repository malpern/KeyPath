# Startup cached reads must not authorize managed replacement

The October 5 fresh-parent trial preserved an exact external Caps profile before
launch, but normal startup replaced it with the generated macOS Function Keys
and space-leader configuration. The retained Caps journal and mutation marker
still belonged to the earlier worker; they were not the cause of the rewrite.

The preserved `startup-log01-result.json` in
`/private/tmp/keypath-marker-fresh-parent-live-01` shows two startup orderings.
At 18:30:10, bootstrap refused to regenerate an unreproducible file at .711, and
the backup task loaded the raw file afterward at .715. At 18:32:03, the fresh
parent parsed that file at .498 and initialized its backup at .500, before
bootstrap attempted its save at .513 and committed 12 generated mappings at .784.

RuntimeCoordinator starts initialization and collection bootstrap in separate
tasks. Initialization calls SaveCoordinator.ensureBackupExists, whose current
configuration read caches the raw disk content. The global reproducibility check
previously accepted a file matching that cache without checking the committed
collection and custom-rule sources. A read therefore became false evidence that
the visual editor owned the file, making preservation depend on startup order.

Remove that cache bypass and retain the existing comparison with generated
content from committed sources. The missing-collection-store migration exception
is unchanged; this trial did not establish that exception as its cause.
`ConfigurationRuleWriteTests.testCachedExternalCapsConfigIsPreservedBeforeManagedSave`
primes the read cache before a managed save and verifies that the raw profile,
both source stores, and journal absence are preserved.
