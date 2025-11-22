# GUI/CLI Overlap Audit — Phase 6

**Date:** 2025-11-20  
**Status:** Audit Complete — Removal Plan Documented

## Summary

After modularizing the CLI into a standalone binary (`KeyPathCLI`), we've identified remaining overlap between GUI and CLI installer flows. This document catalogs shared code paths and outlines a plan to migrate GUI callers to the `InstallerEngine` façade.

## Current State

### ✅ CLI Migration Complete
- **Standalone Binary:** `KeyPathCLI` product builds independently
- **All Commands Routed:** `status`, `install`, `repair`, `uninstall`, `inspect` all use `InstallerEngine`
- **No Direct Calls:** CLI no longer calls `WizardAutoFixer`, `UninstallCoordinator`, or `SystemSnapshotAdapter` directly

### ⚠️ GUI Status (post-migration updates)
- **Wizard Auto-Fix:** Routed through `InstallerEngine.run(...)` (legacy path removed)
- **State Detection:** Wizard and main app now use `InstallerEngine.inspectSystem()` + `SystemContextAdapter` (legacy `SystemSnapshotAdapter` removed 2025-11-21)
- **Uninstall Dialog:** Routed through `InstallerEngine.uninstall(...)`
- **Settings Repair:** Uses façade-backed repair

## Overlap Inventory

### 1. Auto-Fix Operations

**GUI Path:**
- `InstallationWizardView.performAutoFix()` → `WizardAutoFixer.performAutoFix()`
- `SettingsContainerView` → `WizardAutoFixer(kanataManager:)` → `performAutoFix()`

**CLI Path:**
- `KeyPathCLI.runRepair()` → `InstallerEngine.run(intent: .repair, using:)`

**Shared Logic:**
- Both determine actions from system state
- Both execute privileged operations via `PrivilegedOperationsCoordinator`
- Both handle errors and report results

**Migration Target:**
- Replace `WizardAutoFixer` calls with `InstallerEngine.run(intent: .repair, using:)`
- Map `AutoFixAction` enum to `InstallIntent` + `SystemContext` inspection
- Update UI to consume `InstallerReport` instead of `WizardAutoFixer` return values

### 2. System State Detection

**GUI Path (now):**
- `WizardStateManager` → `InstallerEngine.inspectSystem()` → `SystemContextAdapter.adapt()`
- `MainAppStateController` → `SystemValidator.checkSystem()` → `SystemContextAdapter.adapt()`

**CLI Path:**
- `KeyPathCLI.runStatus()` → `InstallerEngine.inspectSystem()` → `SystemContext`

**Shared Logic:**
- Both use `SystemValidator.checkSystem()` for detection
- Both convert to the wizard-compatible format via `SystemContextAdapter`
- Both determine wizard readiness and blocking issues

**Migration Target:** COMPLETE for state detection; next stability tasks live in Phase 7.2 (freshness guard, single health signal).
- Map `SystemContext` fields to existing UI state types (gradual migration)

### 3. Uninstall Operations

**GUI Path:**
- `UninstallKeyPathDialog` → `UninstallCoordinator.uninstall(deleteConfig:)`
- Uses `@StateObject` for reactive UI updates

**CLI Path:**
- `KeyPathCLI.runUninstall()` → `InstallerEngine.uninstall(deleteConfig:using:)` → `UninstallCoordinator` (temporary delegation)

**Shared Logic:**
- Both call the same `UninstallCoordinator` implementation
- Both handle `deleteConfig` flag
- Both capture log output for display

**Migration Target:**
- Complete `InstallerEngine.uninstall()` implementation (currently delegates to `UninstallCoordinator`)
- Update `UninstallKeyPathDialog` to use `InstallerEngine` façade
- Convert `UninstallCoordinator` to a recipe-based approach (future Phase 7 work)

### 4. CLI Fallback in GUI Binary

**Current State:**
- `KeyPathApp/Main.swift` checks for CLI commands and exits early
- Uses `KeyPathCLIEntrypoint.runIfNeeded()` to detect CLI mode

**Rationale:**
- Allows GUI binary to serve as CLI fallback during migration
- Useful for development/testing scenarios

**Removal Plan:**
- Keep fallback until GUI migration is complete and tested
- Remove `KeyPathCLIEntrypoint` import from GUI binary once standalone CLI is stable
- Document that GUI binary no longer supports CLI mode (users must use `KeyPathCLI`)

## Migration Plan

### Phase 6.5: GUI Auto-Fix Migration (Next)

**Steps:**
1. Update `InstallationWizardView.performAutoFix()` to use `InstallerEngine.run(intent: .repair, using:)`
2. Map current `AutoFixAction` enum to `InstallIntent` + context inspection
3. Update UI to consume `InstallerReport` for progress/error display
4. Migrate `SettingsContainerView` repair button similarly
5. Add tests verifying GUI auto-fix uses façade

**Estimated Effort:** 2-3 hours

### Phase 6.6: GUI State Detection Migration

**Steps:**
1. Update `WizardStateManager` to use `InstallerEngine.inspectSystem()`
2. Create adapter to map `SystemContext` → `WizardSystemState` (temporary)
3. Update `MainAppStateController` to use `InstallerEngine.inspectSystem()`
4. Remove `SystemSnapshotAdapter` usage once all callers migrated
5. Add tests verifying state detection consistency

**Estimated Effort:** 3-4 hours

### Phase 6.7: GUI Uninstall Migration

**Steps:**
1. Complete `InstallerEngine.uninstall()` implementation (remove `UninstallCoordinator` delegation)
2. Update `UninstallKeyPathDialog` to use `InstallerEngine.uninstall(deleteConfig:using:)`
3. Convert `@StateObject` reactive updates to consume `InstallerReport.logs`
4. Add tests verifying GUI uninstall uses façade

**Estimated Effort:** 2-3 hours

### Phase 6.8: Remove CLI Fallback

**Steps:**
1. Verify standalone `KeyPathCLI` binary works in all scenarios
2. Update documentation to reference `KeyPathCLI` instead of GUI binary
3. Remove `KeyPathCLIEntrypoint` import from `KeyPathApp/Main.swift`
4. Remove `KeyPathCLIEntrypoint` if no longer needed (or keep for future GUI CLI mode)

**Estimated Effort:** 1 hour

## Benefits After Migration

1. **Single Source of Truth:** All installer logic flows through `InstallerEngine`
2. **Consistent Behavior:** GUI and CLI use identical detection/execution paths
3. **Easier Testing:** Can test installer logic independently of UI
4. **Simplified Maintenance:** One code path to maintain instead of multiple
5. **Better Error Handling:** Structured `InstallerReport` provides consistent error context

## Risks & Mitigations

**Risk:** GUI migration may break existing UI flows  
**Mitigation:** Incremental migration with tests at each step; keep legacy code until migration verified

**Risk:** `SystemContext` may not map cleanly to existing UI state types  
**Mitigation:** Create temporary adapter layer; refactor UI types gradually

**Risk:** Removing CLI fallback may break development workflows  
**Mitigation:** Keep fallback until GUI migration complete; document migration path

## Next Steps

1. ✅ Complete CLI migration (done)
2. ⏳ Start GUI auto-fix migration (Phase 6.5)
3. ⏳ Migrate GUI state detection (Phase 6.6)
4. ⏳ Migrate GUI uninstall (Phase 6.7)
5. ⏳ Remove CLI fallback (Phase 6.8)
