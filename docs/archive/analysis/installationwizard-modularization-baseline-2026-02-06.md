# InstallationWizard Modularization Baseline (2026-02-06)

## Goal
Establish baseline build metrics and a concrete post-release plan to evaluate extracting `InstallationWizard` into its own SwiftPM target.

This is preparatory work for `MAL-88` and does **not** perform target extraction.

## Baseline Environment
- Repository: `KeyPath`
- Date: `2026-02-06`
- Build mode: `debug`
- Build product measured: `KeyPath`
- Build path: `.build-baseline`
- Module cache override: `.build-baseline/ModuleCache.noindex`

## Commands Used
```bash
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build-baseline/ModuleCache.noindex" \
  swift build --build-path .build-baseline -c debug --product KeyPath
```

Then repeated with:
- no file changes (`noop_incremental`)
- a non-installer touch:
  `touch Sources/KeyPathAppKit/UI/ContentView/StatusMessageView.swift`
- an installer touch:
  `touch Sources/KeyPathAppKit/InstallationWizard/UI/Components/WizardButtonBar.swift`

## Timing Results
- `clean`: `74s`
- `noop_incremental`: `1s`
- `non_installer_touch`: `7s`
- `installer_touch`: `7s`

## Initial Read
From this single-run baseline:
- clean builds are the dominant cost
- incremental no-op is very fast
- touching one file in installer vs non-installer currently has similar rebuild cost
- this suggests current target boundaries do not isolate installer compile impact enough

## Post-Release Plan (MAL-88)
1. Define target boundary for `KeyPathInstallationWizard`.
2. Keep behavior unchanged; move files first, refactor later.
3. Add narrow protocol seam from wizard to app/runtime:
   - install/repair/inspect actions via `InstallerEngine`
   - permission and settings navigation hooks
4. Preserve `KeyPathWizardCore` as shared model/state types.
5. Re-run the same build benchmark matrix after extraction.

## Success Criteria
Treat extraction as successful if, after migration:
- non-installer touches no longer trigger wizard recompilation
- installer-only touches rebuild fewer unrelated units
- incremental build median improves by at least `15-25%` for common edit paths
- no release-critical behavior regressions in wizard flows

## Measurement Follow-Up
For stronger confidence, run 3-5 repetitions per scenario and compare medians:
- `clean`
- `noop_incremental`
- `installer_touch`
- `non_installer_touch`

Use the same machine/load profile to reduce noise.
