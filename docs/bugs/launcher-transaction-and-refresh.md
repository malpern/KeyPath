# Launcher deletion poisoned subsequent saves and left stale keyboard icons

Confirmed on the Air: drawer deletion removed Q from RuleCollections.json but left its alias and layer mapping in keypath.kbd. Subsequent tour writes correctly refused an unreproducible global configuration. LauncherStore, drawer additions and launcher settings now use the manager's serialized recoverable transaction rather than direct JSON writes. Failed saves retain previous UI/config state and report an error. Queued edits apply against the latest committed configuration.

A live deletion after this fix revealed a separate display bug: prewarming launcher mappings refreshed the cache but did not replace the active keyboard snapshot. The keyboard now publishes the refreshed mappings including when the drawer previews launcher icons on the base runtime layer, so a removed shortcut disappears without a layer switch.

Regression evidence: testDeleteCommitsGeneratedConfigAndAllowsNextTourSave failed before the transactional fix; testDeletedShortcutDisappearsFromVisibleKeyboardWithoutLayerSwitch failed before the display fix. Both pass, along with queued-edit and preservation-rejection checks. The combined iteration suite passed 51 tests without warnings.

For this Air's already-divergent state, backed up both files, restored missing Q metadata, and compared isolated regenerated output. The only remaining difference was the order of two independent Q/D Dia alias declarations from an older generator. Reordered just those declarations with an exact-diff assertion; the production preservation guard was not weakened. Live Q deletion then updated both files. A subsequent real-tour Hyper+S → Dia save succeeded. Final temporary-shortcut cleanup is recorded in the local iteration verification report.
