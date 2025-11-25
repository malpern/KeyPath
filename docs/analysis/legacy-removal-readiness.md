# Legacy Code Removal Readiness Checklist

This document tracks what needs to be verified before removing `LaunchDaemonInstaller.swift` and other legacy code.

## Overview

**Goal**: Safely remove ~2,768 lines of legacy code (`LaunchDaemonInstaller.swift`) after verifying that extracted services provide equivalent functionality.

**Strategy**: 
1. ✅ Extract services (Phase 2 - Complete)
2. 🔄 Verify behavior equivalence (Current Phase)
3. ⏳ Remove legacy code (Phase 3)

## LaunchDaemonInstaller Public API Coverage

### ✅ Already Extracted (Verified)

| LaunchDaemonInstaller Method | Extracted Service | Status |
|------------------------------|-------------------|--------|
| `generateKanataPlist()` (private) | `PlistGenerator.generateKanataPlist()` | ✅ Delegates |
| `generateVHIDDaemonPlist()` (private) | `PlistGenerator.generateVHIDDaemonPlist()` | ✅ Delegates |
| `generateVHIDManagerPlist()` (private) | `PlistGenerator.generateVHIDManagerPlist()` | ✅ Delegates |
| `isServiceLoaded(serviceID:)` | `ServiceHealthChecker.isServiceLoaded()` | ✅ Equivalent |
| `isServiceHealthy(serviceID:)` | `ServiceHealthChecker.isServiceHealthy()` | ✅ Equivalent |
| `getServiceStatus()` | `ServiceHealthChecker.getServiceStatus()` | ✅ Equivalent |
| `checkKanataServiceHealth()` | `ServiceHealthChecker.checkKanataServiceHealth()` | ✅ Equivalent |
| `installBundledKanataBinaryOnly()` | `KanataBinaryInstaller.installBundledKanata()` | ✅ Equivalent |

### ⚠️ Needs Verification (Covered by Façade)

| LaunchDaemonInstaller Method | Façade Method | Test Status |
|------------------------------|---------------|-------------|
| `createAllLaunchDaemonServices()` | `InstallerEngine.run(intent: .install)` | ⚠️ Needs test |
| `createConfigureAndLoadAllServices()` | `InstallerEngine.run(intent: .install)` | ⚠️ Needs test |
| `loadServices()` | `ServiceBootstrapper.loadService()` | ⚠️ Needs test |
| `restartUnhealthyServices()` | `ServiceBootstrapper.restartServicesWithAdmin()` | ⚠️ Needs test |
| `repairVHIDDaemonServices()` | `InstallerEngine.run(intent: .repair)` | ⚠️ Needs test |
| `installLogRotationService()` | **Not extracted** | ⚠️ Needs extraction or test |

### ❓ Still Used Directly (Needs Migration)

| Caller | Method Used | Migration Path |
|--------|-------------|----------------|
| `PrivilegedOperationsCoordinator` | `createConfigureAndLoadAllServices()` | Use `InstallerEngine.run(intent: .install)` |
| `PrivilegedOperationsCoordinator` | `restartUnhealthyServices()` | Use `ServiceBootstrapper.restartServicesWithAdmin()` |
| `PrivilegedOperationsCoordinator` | `repairVHIDDaemonServices()` | Use `InstallerEngine.run(intent: .repair)` |
| `PrivilegedOperationsCoordinator` | `installLogRotationService()` | Extract or migrate |
| `PrivilegedOperationsCoordinator` | `installBundledKanataBinaryOnly()` | Use `KanataBinaryInstaller.installBundledKanata()` |
| `PrivilegedOperationsCoordinator` | `createAllLaunchDaemonServicesInstallOnly()` | Use `InstallerEngine.run(intent: .install)` |
| `SystemValidator` | `LaunchDaemonInstaller()` (constructor) | Use `ServiceHealthChecker` directly |
| `WizardAutoFixer` | `LaunchDaemonInstaller()` (constructor) | Use `InstallerEngine` façade |
| `KarabinerConflictService` | `wasRecentlyRestarted()` (static) | Extract to `ServiceBootstrapper` |

## Test Coverage Requirements

### Required Tests Before Removal

1. **Behavior Equivalence Tests** (`LegacyRemovalReadinessTests.swift`)
   - ✅ Plist generation delegation verified
   - ✅ Health check equivalence verified
   - ✅ Service status equivalence verified
   - ⚠️ Installation flow equivalence (needs test)
   - ⚠️ Repair flow equivalence (needs test)
   - ⚠️ Service restart equivalence (needs test)

2. **Integration Tests**
   - ⚠️ Full installation flow via `InstallerEngine` matches `LaunchDaemonInstaller`
   - ⚠️ Full repair flow via `InstallerEngine` matches `LaunchDaemonInstaller`
   - ⚠️ Service order preserved (VHID Daemon → VHID Manager → Kanata)

3. **Edge Case Tests**
   - ⚠️ Error handling equivalent (invalid service IDs, missing files, etc.)
   - ⚠️ Permission failures handled the same way
   - ⚠️ Partial failures handled the same way

## Migration Checklist

### Before Removing LaunchDaemonInstaller

- [ ] All direct callers migrated to extracted services or façade
- [ ] All public methods have equivalent implementations
- [ ] Behavior equivalence tests pass
- [ ] Integration tests pass
- [ ] Edge case tests pass
- [ ] Service dependency order preserved
- [ ] Error messages equivalent
- [ ] Log messages equivalent (for debugging)

### Code Locations to Update

1. **PrivilegedOperationsCoordinator.swift**
   - Replace `LaunchDaemonInstaller()` calls with `InstallerEngine` or extracted services
   - ~10 direct usages

2. **SystemValidator.swift**
   - Replace `LaunchDaemonInstaller()` constructor with `ServiceHealthChecker.shared`
   - ~2 usages

3. **WizardAutoFixer.swift**
   - Replace `LaunchDaemonInstaller()` with `InstallerEngine` façade
   - ~1 usage

4. **KarabinerConflictService.swift**
   - Extract `wasRecentlyRestarted()` to `ServiceBootstrapper`
   - ~1 usage

## Remaining Work

### High Priority
1. **Extract Log Rotation Service** (~50 lines)
   - `installLogRotationService()` needs extraction
   - Or verify it's not critical and can be removed

2. **Migrate Direct Callers**
   - Update `PrivilegedOperationsCoordinator` to use façade
   - Update `SystemValidator` to use `ServiceHealthChecker`
   - Update `WizardAutoFixer` to use `InstallerEngine`

3. **Add Behavior Equivalence Tests**
   - Installation flow tests
   - Repair flow tests
   - Service restart tests

### Medium Priority
1. **Extract Static Methods**
   - `wasRecentlyRestarted()` → `ServiceBootstrapper`
   - `kanataServiceID`, `kanataPlistPath` → Constants file

2. **Documentation Updates**
   - Update README files
   - Archive legacy documentation

### Low Priority
1. **Code Cleanup**
   - Remove unused private methods
   - Consolidate duplicate logic
   - Update comments

## Risk Assessment

### Low Risk (Safe to Remove)
- ✅ Plist generation methods (already delegated)
- ✅ Health check methods (already extracted)
- ✅ Service status methods (already extracted)

### Medium Risk (Needs Testing)
- ⚠️ Installation flow methods (covered by façade, needs verification)
- ⚠️ Repair flow methods (covered by façade, needs verification)
- ⚠️ Service restart methods (covered by extracted service, needs verification)

### High Risk (Needs Careful Migration)
- ⚠️ Log rotation service (not extracted)
- ⚠️ Static utility methods (used by other services)
- ⚠️ Error handling edge cases (needs comprehensive testing)

## Success Criteria

Before marking Phase 3 complete:

1. ✅ All tests pass (60+ tests)
2. ✅ No direct `LaunchDaemonInstaller()` calls in production code
3. ✅ Behavior equivalence verified for all public methods
4. ✅ Integration tests verify full flows work identically
5. ✅ Edge cases handled equivalently
6. ✅ Documentation updated

## Next Steps

1. **Complete Test Coverage** (Current)
   - Add behavior equivalence tests
   - Add integration tests
   - Add edge case tests

2. **Migrate Direct Callers**
   - Update `PrivilegedOperationsCoordinator`
   - Update `SystemValidator`
   - Update `WizardAutoFixer`

3. **Extract Remaining Methods**
   - Log rotation service
   - Static utility methods

4. **Final Verification**
   - Run full test suite
   - Manual smoke tests
   - Code review

5. **Remove Legacy Code**
   - Delete `LaunchDaemonInstaller.swift`
   - Update imports
   - Clean up references

