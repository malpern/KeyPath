# SMAppService Implementation Plan

## Overview

This document outlines the safest and most incremental approach to implementing SMAppService for Kanata LaunchDaemon management, based on the POC findings and external validation.

## Implementation Strategy

### Phase 1: Foundation (Low Risk)
**Goal:** Add infrastructure without changing behavior

1. **Add Feature Flag**
   - Add `useSMAppServiceForDaemon` to `FeatureFlags` (default: `false`)
   - Persist in UserDefaults for gradual rollout
   - Add UI toggle in Diagnostics (hidden by default, can be enabled for testing)

2. **Create KanataDaemonManager**
   - Similar pattern to `HelperManager` (already uses SMAppService)
   - Wraps SMAppService.daemon() for Kanata
   - Provides status checking, registration, unregistration
   - Uses same test seam pattern (`smServiceFactory`) for testability

3. **Add Plist to App Bundle**
   - Create `com.keypath.kanata.plist` in app bundle
   - Reference bundled Kanata binary (not system path)
   - Ensure proper codesigning

### Phase 2: Detection & Migration Logic (Medium Risk)
**Goal:** Detect existing installations and migrate safely

1. **Migration Detection**
   - Check for legacy plist at `/Library/LaunchDaemons/com.keypath.kanata.plist`
   - Check launchctl status: `launchctl print system/com.keypath.kanata`
   - Check SMAppService status: `.enabled` or `.notRegistered`
   - Determine which method is active

2. **Migration Function**
   - Only runs if feature flag enabled AND legacy detected
   - Requires admin privileges (for launchctl cleanup)
   - Steps:
     1. Verify legacy installation exists
     2. Stop service: `launchctl bootout system/com.keypath.kanata`
     3. Remove plist: `sudo rm /Library/LaunchDaemons/com.keypath.kanata.plist`
     4. Register via SMAppService (requires user approval)
     5. Verify service starts correctly
     6. Log migration success/failure

3. **Rollback Function**
   - Unregister via SMAppService
   - Reinstall via existing `LaunchDaemonInstaller` path
   - Verify service starts correctly

### Phase 3: Integration (Medium Risk)
**Goal:** Integrate SMAppService path into existing flows

1. **Update LaunchDaemonInstaller**
   - Add `useSMAppService` parameter (default: `false`)
   - If enabled, delegate to `KanataDaemonManager`
   - If disabled, use existing launchctl path
   - Maintain backward compatibility

2. **Update Installation Wizard**
   - Check feature flag before installation
   - Use SMAppService path if enabled
   - Fall back to launchctl if SMAppService fails
   - Show appropriate prompts (user approval vs admin password)

3. **Update Status Checking**
   - Check both methods (SMAppService status + launchctl status)
   - Log which method is active
   - Show in Diagnostics view

### Phase 4: Hybrid Approach (Low Risk)
**Goal:** Use best tool for each operation

1. **Registration: SMAppService**
   - Better UX (one-time approval)
   - Better error messages
   - Structured status API

2. **Status/Restart: launchctl**
   - Faster operations (<0.1s vs ~10s)
   - More control (kickstart, enable/disable)
   - Existing proven path

3. **Implementation**
   - Register via SMAppService
   - Check status via launchctl: `launchctl print system/com.keypath.kanata`
   - Restart via launchctl: `launchctl kickstart -k system/com.keypath.kanata`
   - Unregister via SMAppService (when needed)

### Phase 5: Rollback UI (Low Risk)
**Goal:** Add user-facing rollback in Diagnostics

1. **Add Rollback Button**
   - Show in Diagnostics if SMAppService method is active
   - Warn user about switching back to launchctl
   - Require confirmation

2. **Add Migration Button**
   - Show in Diagnostics if legacy method detected AND feature flag enabled
   - Explain benefits (one-time approval vs admin password)
   - Require admin privileges

3. **Status Display**
   - Show which method is active
   - Show migration eligibility
   - Show rollback availability

## Safety Measures

### 1. Feature Flag Protection
- Default: `false` (launchctl path)
- Only enable for testing/gradual rollout
- Can be disabled instantly if issues arise

### 2. Dual Path Support
- Always check both methods
- Never break existing installations
- Graceful fallback if SMAppService fails

### 3. Migration Safety
- Only migrate if legacy detected
- Require admin privileges
- Verify service health after migration
- Log all migration attempts

### 4. Rollback Safety
- One-click rollback to launchctl
- Preserve service configuration
- Verify service health after rollback

### 5. Error Handling
- Catch and log all errors
- Fall back to launchctl on SMAppService failure
- Never leave system in broken state
- Clear error messages for users

## Testing Strategy

### Unit Tests
- Test `KanataDaemonManager` status checking
- Test migration detection logic
- Test rollback logic
- Mock SMAppService for testing

### Integration Tests
- Test migration flow (legacy → SMAppService)
- Test rollback flow (SMAppService → launchctl)
- Test hybrid approach (register SMAppService, restart launchctl)
- Test error handling and fallbacks

### Manual Testing
- Test on clean install (new users)
- Test migration from existing install
- Test rollback functionality
- Test feature flag toggle
- Test error scenarios

## Rollout Plan

### Stage 1: Internal Testing (Week 1)
- Enable feature flag for internal testing
- Test all migration/rollback scenarios
- Fix any issues discovered

### Stage 2: Beta Testing (Week 2-3)
- Enable feature flag for beta users
- Monitor error rates and user feedback
- Collect metrics on migration success/failure

### Stage 3: Gradual Rollout (Week 4+)
- Enable for 10% of new installations
- Monitor closely for issues
- Gradually increase percentage
- Keep launchctl as fallback

### Stage 4: Full Rollout (Week 8+)
- Enable by default for new installations
- Keep migration path for existing users
- Keep rollback available indefinitely

## Code Structure

```
Sources/KeyPath/
├── Managers/
│   └── KanataDaemonManager.swift      # New: SMAppService wrapper for Kanata
├── Core/
│   └── LaunchDaemonInstaller.swift    # Updated: Add SMAppService path
├── Utilities/
│   └── FeatureFlags.swift             # Updated: Add useSMAppServiceForDaemon
└── UI/
    └── DiagnosticsView.swift          # Updated: Add migration/rollback UI
```

## Key Files to Create/Modify

### New Files
1. `Sources/KeyPath/Managers/KanataDaemonManager.swift`
   - Similar to `HelperManager` but for Kanata daemon
   - Handles SMAppService registration/unregistration
   - Provides status checking

2. `Resources/com.keypath.kanata.plist`
   - Kanata LaunchDaemon plist for SMAppService
   - References bundled Kanata binary
   - Properly configured for app bundle context

### Modified Files
1. `Sources/KeyPath/Utilities/FeatureFlags.swift`
   - Add `useSMAppServiceForDaemon` flag

2. `Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift`
   - Add SMAppService path option
   - Maintain backward compatibility

3. `Sources/KeyPath/UI/DiagnosticsView.swift`
   - Add migration/rollback UI
   - Show active method
   - Add feature flag toggle (hidden by default)

## Risk Mitigation

### High Risk Areas
1. **Migration Logic**
   - Risk: Breaking existing installations
   - Mitigation: Extensive testing, feature flag, rollback path

2. **Service Dependencies**
   - Risk: VirtualHID services must start before Kanata
   - Mitigation: Keep dependency order, test thoroughly

3. **TCC Permissions**
   - Risk: Losing Input Monitoring/Accessibility permissions
   - Mitigation: POC confirmed no TCC regression risk

### Low Risk Areas
1. **Feature Flag**
   - Risk: None (default disabled)
   - Mitigation: Can be disabled instantly

2. **Rollback UI**
   - Risk: None (additive only)
   - Mitigation: Only adds functionality

3. **Status Checking**
   - Risk: None (read-only)
   - Mitigation: Only reads status, doesn't modify

## Success Criteria

### Phase 1 Complete
- ✅ Feature flag added and working
- ✅ KanataDaemonManager created
- ✅ Plist added to app bundle
- ✅ No behavior changes (flag disabled)

### Phase 2 Complete
- ✅ Migration detection working
- ✅ Migration function working
- ✅ Rollback function working
- ✅ Tests passing

### Phase 3 Complete
- ✅ Integration with LaunchDaemonInstaller
- ✅ Installation wizard updated
- ✅ Status checking updated
- ✅ No regressions

### Phase 4 Complete
- ✅ Hybrid approach implemented
- ✅ Registration via SMAppService
- ✅ Status/restart via launchctl
- ✅ Performance acceptable

### Phase 5 Complete
- ✅ Rollback UI added
- ✅ Migration UI added
- ✅ Status display updated
- ✅ User documentation updated

## Timeline Estimate

- **Phase 1:** 2-3 days
- **Phase 2:** 3-4 days
- **Phase 3:** 2-3 days
- **Phase 4:** 1-2 days
- **Phase 5:** 1-2 days

**Total:** ~2 weeks of development + testing

## Open Questions

1. Should we migrate existing users automatically or require opt-in?
   - **Recommendation:** Opt-in via Diagnostics UI (safer)

2. Should we keep both methods indefinitely or deprecate launchctl?
   - **Recommendation:** Keep both indefinitely (safety net)

3. Should we use hybrid approach by default or pure SMAppService?
   - **Recommendation:** Hybrid (best of both worlds)

4. How do we handle VirtualHID service dependencies with SMAppService?
   - **Recommendation:** Keep launchctl for VirtualHID, SMAppService only for Kanata

## Next Steps

1. Review this plan with team
2. Create GitHub issues for each phase
3. Start with Phase 1 (foundation)
4. Test thoroughly before moving to next phase
5. Monitor metrics and user feedback throughout rollout

