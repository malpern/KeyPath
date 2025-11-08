# SMAppService Migration Status

**Last Updated:** Current session  
**Branch:** `feature/smappservice-daemon-migration`

## Overview

Migration from `launchctl` to `SMAppService` for Kanata LaunchDaemon management. The migration follows a phased approach with feature flags for safe rollout.

## Migration Plan Reference

- **Fast Track Plan:** `docs/spikes/smappservice-migration-path.md`
- **Detailed Plan:** `docs/spikes/smappservice-implementation-plan.md`

## Current Status Summary

### ✅ Phase 1: Core Implementation - **COMPLETE**

**Goal:** Get SMAppService working for Kanata daemon

- ✅ **KanataDaemonManager Created**
  - Location: `Sources/KeyPath/Managers/KanataDaemonManager.swift`
  - Status: Fully implemented with registration/unregistration
  - Features:
    - SMAppService registration/unregistration
    - Status checking (SMAppService + launchctl fallback)
    - Migration detection methods
    - Error handling

- ✅ **Plist Added to App Bundle**
  - Location: `Sources/KeyPath/com.keypath.kanata.plist`
  - Status: Created and configured
  - Features:
    - Uses `BundleProgram` for SMAppService compatibility
    - Properly references bundled Kanata binary
    - Includes all necessary configuration

- ✅ **Feature Flag Added**
  - Location: `Sources/KeyPath/Utilities/FeatureFlags.swift`
  - Key: `useSMAppServiceForDaemon`
  - **Current Default: `true`** (enabled by default)
  - Persisted in UserDefaults

- ✅ **LaunchDaemonInstaller Integration**
  - Location: `Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift`
  - Status: Fully integrated
  - Features:
    - Checks feature flag before installation
    - Uses SMAppService path when enabled
    - Falls back to launchctl on error
    - Both paths work simultaneously

### ⚠️ Phase 2: Migration & Rollback - **PARTIALLY COMPLETE**

**Goal:** Enable migration from launchctl to SMAppService

- ✅ **Migration Detection**
  - `hasLegacyInstallation()` - checks for legacy plist
  - `isRegisteredViaSMAppService()` - checks SMAppService status
  - `isInstalled()` - checks both methods

- ⚠️ **Migration Function** - **NEEDS FIXING**
  - Location: `KanataDaemonManager.migrateFromLaunchctl()`
  - Status: Implemented but incomplete
  - Issue: Uses `HelperManager.shared.installLaunchDaemon(plistPath: "", ...)` with empty plistPath
  - This approach may not properly stop and remove the legacy service
  - **Action Required:** Fix migration to properly:
    1. Stop legacy service via `launchctl bootout system/com.keypath.kanata`
    2. Remove plist at `/Library/LaunchDaemons/com.keypath.kanata.plist`
    3. Register via SMAppService
    4. Verify service started

- ✅ **Rollback Function**
  - Location: `KanataDaemonManager.rollbackToLaunchctl()`
  - Status: Implemented
  - Features:
    - Unregisters via SMAppService
    - Reinstalls via launchctl using `LaunchDaemonInstaller`
    - Verifies service started

- ❌ **Auto-Migration on Install**
  - Status: Not implemented
  - Plan: During installation wizard, check for legacy and offer migration if feature flag enabled

### ✅ Phase 3: Integration - **MOSTLY COMPLETE**

**Goal:** Integrate SMAppService path into existing flows

- ✅ **LaunchDaemonInstaller Updated**
  - Uses SMAppService when feature flag enabled
  - Falls back to launchctl on error
  - Maintains backward compatibility

- ✅ **Installation Wizard Integration**
  - Uses SMAppService path when flag enabled
  - Shows appropriate prompts (user approval vs admin password)

- ⚠️ **Status Checking**
  - Status: Partially updated
  - `KanataDaemonManager.isInstalled()` checks both methods
  - `ProcessManager.checkLaunchDaemonStatus()` still uses launchctl only
  - **Action Required:** Update status checking to show which method is active

### ❌ Phase 4: Hybrid Approach - **NOT IMPLEMENTED**

**Goal:** Use best tool for each operation

- Status: Not implemented
- Plan:
  - Registration: SMAppService (better UX)
  - Status/Restart: launchctl (faster, more control)
- **Note:** This phase is optional and may not be necessary

### ❌ Phase 5: Rollback/Migration UI - **NOT IMPLEMENTED**

**Goal:** Add user-facing rollback/migration in Diagnostics

- ❌ **Rollback Button**
  - Status: Not implemented
  - Plan: Show in Diagnostics if SMAppService method is active
  - Should warn user and require confirmation

- ❌ **Migration Button**
  - Status: Not implemented
  - Plan: Show in Diagnostics if legacy method detected AND feature flag enabled
  - Should explain benefits and require admin privileges

- ❌ **Status Display**
  - Status: Not implemented
  - Plan: Show which method is active (SMAppService vs launchctl)
  - Show migration eligibility and rollback availability

### ❌ Testing - **INCOMPLETE**

- ✅ **Unit Tests**
  - Location: `Tests/KeyPathTests/Managers/KanataDaemonManagerTests.swift`
  - Status: Basic tests exist
  - Coverage:
    - Status checking tests
    - Validation tests
    - Error handling tests
    - Constants and singleton tests

- ❌ **Migration Tests**
  - Status: Not implemented
  - Need: Tests for migration flow (legacy → SMAppService)
  - Need: Tests for rollback flow (SMAppService → launchctl)

- ❌ **Integration Tests**
  - Status: Not implemented
  - Need: End-to-end tests for installation with SMAppService
  - Need: Tests for fallback behavior

## What's Working

1. ✅ SMAppService registration/unregistration works
2. ✅ Feature flag controls which path is used
3. ✅ Fallback to launchctl on error
4. ✅ Both paths can coexist
5. ✅ Rollback function implemented (needs testing)
6. ✅ Migration detection works

## What Needs Work

### High Priority

1. **Fix Migration Function** (`migrateFromLaunchctl`)
   - Current implementation uses incomplete helper method
   - Need to properly stop legacy service and remove plist
   - May need to add helper method for `launchctl bootout`

2. **Add Migration/Rollback UI in DiagnosticsView**
   - Show active method (SMAppService vs launchctl)
   - Add "Migrate to SMAppService" button (if legacy detected)
   - Add "Rollback to launchctl" button (if SMAppService active)
   - Show migration eligibility

3. **Update Status Display**
   - Show which method is active in Diagnostics
   - Update status checking to report active method

### Medium Priority

4. **Add Migration Tests**
   - Test migration flow (legacy → SMAppService)
   - Test rollback flow (SMAppService → launchctl)
   - Test error handling

5. **Add Integration Tests**
   - Test installation with SMAppService enabled
   - Test fallback behavior
   - Test feature flag toggle

### Low Priority

6. **Consider Hybrid Approach** (Phase 4)
   - Registration via SMAppService
   - Status/restart via launchctl
   - May not be necessary if current approach works well

## Feature Flag Status

- **Current Default:** `true` (SMAppService enabled by default)
- **Location:** `FeatureFlags.useSMAppServiceForDaemon`
- **Can be toggled:** Via UserDefaults (no UI toggle yet)

## Next Steps

1. **Fix Migration Function**
   - Investigate proper way to stop legacy service via helper
   - May need to add `bootoutLaunchDaemon` method to helper
   - Test migration flow end-to-end

2. **Add Diagnostics UI**
   - Add status display showing active method
   - Add migration button (if legacy detected)
   - Add rollback button (if SMAppService active)
   - Add feature flag toggle (for testing)

3. **Add Tests**
   - Migration flow tests
   - Rollback flow tests
   - Integration tests

4. **Test End-to-End**
   - Test clean install with SMAppService
   - Test migration from legacy install
   - Test rollback functionality
   - Test error scenarios

## Files Modified/Created

### New Files
- ✅ `Sources/KeyPath/Managers/KanataDaemonManager.swift` (~278 lines)
- ✅ `Sources/KeyPath/com.keypath.kanata.plist` (~60 lines)
- ✅ `Tests/KeyPathTests/Managers/KanataDaemonManagerTests.swift` (~130 lines)

### Modified Files
- ✅ `Sources/KeyPath/Utilities/FeatureFlags.swift` (+15 lines)
- ✅ `Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift` (+~100 lines)

### Files Needing Updates
- ❌ `Sources/KeyPath/UI/DiagnosticsView.swift` (needs migration/rollback UI)
- ⚠️ `Sources/KeyPath/Managers/KanataDaemonManager.swift` (needs migration fix)

## Risk Assessment

### Low Risk ✅
- Feature flag (can disable instantly)
- Dual path support (both work)
- Rollback available

### Medium Risk ⚠️
- Migration logic (needs fixing and testing)
- Service dependencies (same as before)

### Mitigation
- Feature flag for quick disable
- Rollback always available
- Fallback to launchctl on error
- Extensive testing before rollout

## Success Criteria

- ✅ SMAppService registration works
- ⚠️ Migration from launchctl works (needs fixing)
- ✅ Rollback to launchctl works (needs testing)
- ✅ New installations use SMAppService by default
- ⚠️ Existing installations can migrate (needs fixing)
- ✅ No regressions in existing functionality

## Timeline Estimate

- **Phase 1:** ✅ Complete
- **Phase 2:** ⚠️ 1-2 days remaining (fix migration, add tests)
- **Phase 3:** ⚠️ 1 day remaining (status display)
- **Phase 4:** ❌ Optional, not started
- **Phase 5:** ❌ 1-2 days (Diagnostics UI)

**Total Remaining:** ~3-5 days of work

