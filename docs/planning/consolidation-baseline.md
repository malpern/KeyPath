# Consolidation baseline and first work packet

Date: 2026-09-04. Source baseline: `a12bb07d5`.
Related: [approved plan](catalog-led-consolidation-plan.md).

This is a source-path inventory, not an assertion that every feature has passed
live QA. Usage is unknown for all areas; no telemetry or user-data inspection was
performed. Significant UI changes require discussion before implementation.

## Feature disposition inventory

Paths below are relative to `Sources/KeyPathAppKit` unless noted otherwise.

| Surface | Owners / entry points | Existing verification to reuse | Disposition / compatibility obligation |
| --- | --- | --- | --- |
| Catalog and pack management | `UI/Gallery`, `Services/Packs/PackInstaller.swift`, `InstalledPackTracker`, `RuleCollectionCatalog` | `PackInstallerRenderTests`, `PackDependencyTests`, `MultiCollectionConflictTests` | Core; preserve pack IDs, installed records, custom settings, previews, and discovery. |
| Remaps, tap-hold, layers, timing | `UI/Rules`, `UI/Pickers/RecordingCoordinator.swift`, `RuleCollectionsManager`, `Sources/KeyPathRulesCore` | `MapperConflictAndSaveTests`, `HomeRowModsConfigTests`, `ConfigRoundTripTests` | Core; preserve rule IDs, source stores, activators, and generated semantics. |
| Overlay / keyboard layouts | `UI/Overlay`, keyboard visualization services, `PhysicalLayout`, `LogicalKeymap` | layout and snapshot targets, `KanataConfigurationGeneratorSnapshotTests` | Core; selected geometry and logical labels remain independent. |
| Install / runtime / recovery | `Sources/KeyPathInstallationWizard`, `PermissionOracle`, `ServiceLifecycleCoordinator` | `InstallerStateMatrixGoldenTests`, `ServiceLifecycleCoordinatorTests` | Core; retain identities, permission evidence, pending approval, and readiness contracts. |
| App launching / window actions | `Services/ActionDispatcher.swift`, launcher/window collection configuration | action and configuration tests; installed-app validation still required | Keep existing bounded actions; no workflow engine expansion. |
| Karabiner import | `UI/Overlay/KarabinerImportSheet.swift`, `InstallationWizard/WizardKarabinerImportPage.swift`, `Services/Karabiner` | Karabiner converter tests | Freeze expansion; document supported conversions before changing existing import behavior. |
| QMK import / keyboard discovery | `UI/Overlay/QMKImportSheet.swift`, `QMKKeyboardSearchView.swift`, `Services/Import` | QMK parser/import tests | Preserve working layouts; defer exhaustive conversion and new hardware protocols. |
| AI configuration | `UI/Settings/SettingsView+AIConfig.swift`, generated-save path | `AIConfigGenerationTests`; save-boundary tests added in first packet | Defer expansion; no entry-point removal in this packet. Preserve raw content. |
| Insights / plugins | `Sources/KeyPathInsights`, `UI/Settings/PluginCatalogCard.swift`, gallery insights | existing analytics tests and issue #204; live end-to-end proof outstanding | Defer expansion; distinguish mapping feedback from standalone analytics before retirement. |
| Onboarding rendering | `UI/Rules/FirstSuccessOnboardingDialog.swift`, `UI/KeyboardStage` | rendering goldens / snapshots | Freeze expansion; retain current experience and fix regressions. |
| CLI / advanced configuration | `Sources/KeyPathCLI`, `CLI/ConfigFacade.swift`, raw/external save paths | CLI facade and integration tests | Preserve command contracts and arbitrary config files; no silent conversion to managed mode. |
| OS integration | `Intents`, app URL handling | intent/action tests and supported-OS qualification | Compatibility continues; speculative expansion deferred. |

## Configuration mutation-path matrix

These are distinct operational paths, not a claim that all share one transaction.

| Entry | Persistence and notifications | Reload / result | Recovery / gap |
| --- | --- | --- | --- |
| Collection enable/disable and custom rules | Public API mutates manager state; `regenerateConfigFromCollections` validates/writes config, then writes collection/custom stores, then posts rules notification and sound | Calls optional `onRulesChanged: () async -> Void`; runtime callback discards `ReloadResult`; returns Boolean save success | Snapshot rollback exists for several mutations; not universal. Reload result does not reach mutation caller. |
| Collection timing / picker edits | Same regeneration path; several setters discard its Boolean | Same callback | Audit each setter before migration; do not assume it has snapshot recovery. |
| Mapper saved through `SaveCoordinator.saveMapping` | Saves a custom rule with `skipReload: true` after backing up current config | Explicit reload handler; accepts applied or pending | Restores config file after rejected/failed; does not establish a complete cross-store transaction. |
| Catalog pack install | `PackInstaller` branches for managed/system, associated collection, and custom-rule packs; updates installed metadata with rollback checks | Manager Boolean; multi-rule path suppresses intermediate reloads | Config may be regenerated per rule despite one final reload. Metadata and rules are separate writes. |
| Pack removal / quick settings | Removal may regenerate once per removed rule; quick-setting path updates rules and record | Manager regeneration; some results discarded | Not one universal pack transaction; retain existing preservation prompts until reviewed. |
| Generated/raw save through `SaveCoordinator.saveGeneratedConfig` | Validates, snapshots prior config, atomically writes raw file, parses mappings | Explicit reload handler with four dispositions; public save result originally collapsed them to Boolean | Config backup restore/fallback; source-store synchronization and recovery status need separate design. |
| CLI apply | `ConfigFacade.applyConfiguration` loads source stores, reconciles leader preference, saves generated config | Boolean reload result; distinct CLI result type | Dry run restores temporary preference; real apply is not the app transaction path. |
| CLI restore | `ConfigFacade.restoreConfig` restores directory content; optional reload | Optional Boolean reload success | Directory operation with separate compatibility/recovery requirements; do not treat as a single-rule edit. |
| External editor | File already changed; watcher invokes `ConfigHotReloadService.handleExternalChange` to validate and apply | Four dispositions projected into success/pending/message | External file ownership differs; cannot blindly overwrite newer external content on recovery. |
| Startup/defaults/import/repair utilities | `ConfigurationService` initial-config and raw-write utilities; migration/backup callers | Caller-specific | Audit raw writer call sites before unifying ownership; initialization is not necessarily a user edit. |

Source anchors: `Managers/RuntimeCoordinator.swift` callback and
`applyPersistedRuleChanges`; `Managers/SaveCoordinator.swift`;
`Services/RuleCollections/RuleCollectionsManager+Migrations.swift`;
`Services/Packs/PackInstaller.swift`; `CLI/ConfigFacade.swift`;
`Services/Configuration/ConfigHotReloadService.swift`.

## First bounded implementation

Preserve the existing reload outcome at the `SaveCoordinator` result boundary
for both generated and mapping saves, including rejection/failure. Preserve
existing Boolean success semantics for callers during migration: saved/pending
remains a successful save, but must not be indistinguishable from applied.
Pre-reload validation/write failures have no reload result.

Use temporary configuration and rule stores, with an injected reload closure.
Exercise all four outcomes through a real save operation, asserting the returned
disposition, exactly one reload attempt, and resulting file content. Verify
validation rejection never calls reload or replaces the original file.

This is result preservation, not completion of Phase 1. No status presentation,
conflict policy, catalog layout, or feature removal changes are included. The
next packet must unify transaction ownership and multi-store recovery; merely
propagating failure to existing Boolean callers is unsafe without checking their
rollback/retry behavior.

## Baseline limits and next gates

First packet validation:

- Baseline save suite: 3 tests passed before edits. Candidate save suite: 12
  tests passed, covering generated and mapping saves plus validation rejection.
- Stable-Xcode test builds passed without compiler warnings. Accessibility
  checker passed across 379 files; SwiftFormat 0.61.1 left both Swift files unchanged.
- Full safe gate completed with four snapshot failures: home-row fast typing,
  per-finger controls, typing-feel slider, and repair settings. All four also
  failed after temporarily replacing both changed Swift files with their
  `origin/master` versions; candidate files were restored byte-for-byte.
- Three home-row references expected 1300x638 versus actual 1300x586; repair
  settings failed pixel precision. No reference images or UI files changed.
- Logs: `/tmp/keypath-consolidation-tests.log`,
  `/tmp/keypath-consolidation-full.log`, and
  `/tmp/keypath-consolidation-master-snapshots.log` on the executing Mac.
- Remote review gate selected. The PR must remain unmerged until required
  review/CI and repository merge approval gates are satisfied.

- Existing `codex/module-split-spike` differs from master only in `Package.swift`
  (17 additions / 1 deletion at inspection). It is a proposal, not a completed
  extraction; do not adopt without inspecting its current worktree and tests.
- Existing setup/UX worktrees remain untouched. Coordinate before working there.
- Latest local debug log ends August 14 and is not live health evidence.
- September 4 coverage run 33874656723 stopped at 75 GiB free against a 100 GiB
  reserve. This packet uses local isolated tests; runner repair is still a gate
  before claiming refreshed broad CI coverage.
- Existing golden configs include simple remap, Caps/Escape/Hyper, home-row mods,
  and Vim navigation. Reuse them as compatibility fixtures rather than replacing
  expected output to make refactors pass.
- Physical input, clean setup, signed upgrade, catalog interaction, and recovery
  QA remain unexecuted here. Phase 0's full exit gate remains open until the
  remaining raw-writer inventory and behavior evidence are collected.
