# SMAppService Migration Path (Fast Track)

## Overview

Direct migration path to SMAppService with minimal phases. Focus on getting it working quickly while maintaining essential safety.

## Migration Strategy

### Phase 1: Core Implementation (3-4 days)
**Goal:** Get SMAppService working for Kanata daemon

1. **Create KanataDaemonManager**
   - Copy pattern from `HelperManager` (already uses SMAppService)
   - Handle registration/unregistration
   - Status checking
   - Error handling

2. **Add Plist to App Bundle**
   - Create `com.keypath.kanata.plist` in app bundle
   - Reference bundled Kanata binary
   - Ensure proper codesigning

3. **Update LaunchDaemonInstaller**
   - Add `useSMAppService` parameter (default: `false` for now)
   - If enabled, use `KanataDaemonManager`
   - If disabled, use existing launchctl path
   - Keep both paths working

4. **Add Feature Flag**
   - Add `useSMAppServiceForDaemon` to `FeatureFlags`
   - Default: `false` (launchctl)
   - Can toggle in Diagnostics for testing

### Phase 2: Migration & Rollback (2-3 days)
**Goal:** Enable migration from launchctl to SMAppService

1. **Migration Detection**
   - Check for legacy plist: `/Library/LaunchDaemons/com.keypath.kanata.plist`
   - Check launchctl status
   - Check SMAppService status
   - Determine active method

2. **Migration Function**
   - Stop legacy service: `launchctl bootout system/com.keypath.kanata`
   - Remove plist: `sudo rm /Library/LaunchDaemons/com.keypath.kanata.plist`
   - Register via SMAppService
   - Verify service starts

3. **Rollback Function**
   - Unregister via SMAppService
   - Reinstall via existing `LaunchDaemonInstaller` path
   - Verify service starts

4. **Auto-Migration on Install**
   - During installation wizard, check for legacy
   - If found AND feature flag enabled, offer migration
   - User can choose: migrate or keep launchctl

### Phase 3: Enable by Default (1 day)
**Goal:** Make SMAppService the default for new installations

1. **Change Default**
   - Set feature flag default to `true` for new installations
   - Keep launchctl as fallback if SMAppService fails
   - Existing installations keep launchctl (no auto-migration)

2. **Update Installation Wizard**
   - Use SMAppService by default
   - Fall back to launchctl on error
   - Show appropriate prompts

3. **Add Diagnostics UI**
   - Show active method (SMAppService vs launchctl)
   - Add "Migrate to SMAppService" button (if legacy detected)
   - Add "Rollback to launchctl" button (if SMAppService active)

## Implementation Details

### KanataDaemonManager Structure

```swift
@MainActor
class KanataDaemonManager {
    static let shared = KanataDaemonManager()
    static let kanataServiceID = "com.keypath.kanata"
    static let kanataPlistName = "com.keypath.kanata.plist"
    
    // Similar to HelperManager pattern
    nonisolated(unsafe) static var smServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
        NativeSMAppService(wrapped: ServiceManagement.SMAppService.daemon(plistName: plistName))
    }
    
    func isInstalled() -> Bool { /* check SMAppService status */ }
    func register() async throws { /* register via SMAppService */ }
    func unregister() async throws { /* unregister via SMAppService */ }
    func migrateFromLaunchctl() async throws { /* migration logic */ }
    func rollbackToLaunchctl() async throws { /* rollback logic */ }
}
```

### Plist Configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.kanata</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BUNDLE_PROGRAM}</string>
        <string>--port</string>
        <string>${TCP_PORT}</string>
        <string>--config</string>
        <string>${CONFIG_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/com.keypath.kanata.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/com.keypath.kanata.stderr.log</string>
</dict>
</plist>
```

### LaunchDaemonInstaller Integration

```swift
func installKanataDaemon(useSMAppService: Bool = FeatureFlags.useSMAppServiceForDaemon) async throws {
    if useSMAppService {
        // New SMAppService path
        try await KanataDaemonManager.shared.register()
    } else {
        // Existing launchctl path
        try await installViaLaunchctl()
    }
}
```

### Migration Logic

```swift
func migrateFromLaunchctl() async throws {
    // 1. Check if legacy exists
    guard FileManager.default.fileExists(atPath: LaunchDaemonInstaller.kanataPlistPath) else {
        throw KanataDaemonError.noLegacyInstallation
    }
    
    // 2. Stop legacy service (requires admin)
    try await HelperManager.shared.executePrivilegedCommand(
        "launchctl bootout system/\(LaunchDaemonInstaller.kanataServiceID)"
    )
    
    // 3. Remove plist (requires admin)
    try await HelperManager.shared.executePrivilegedCommand(
        "rm \(LaunchDaemonInstaller.kanataPlistPath)"
    )
    
    // 4. Register via SMAppService
    try await register()
    
    // 5. Verify service started
    try await verifyServiceRunning()
}
```

## Safety Measures

### Essential Safety
1. **Feature Flag** - Can disable instantly
2. **Dual Path** - Both methods work simultaneously
3. **Fallback** - Always fall back to launchctl on error
4. **Rollback** - One-click rollback available

### Migration Safety
- Only migrate if legacy detected
- Require admin privileges
- Verify service health after migration
- Log all operations

## Testing Strategy

### Quick Testing
1. Test SMAppService registration/unregistration
2. Test migration flow (legacy → SMAppService)
3. Test rollback flow (SMAppService → launchctl)
4. Test error handling and fallbacks

### Manual Testing Checklist
- [ ] Clean install uses SMAppService
- [ ] Legacy install can migrate
- [ ] Rollback works correctly
- [ ] Feature flag toggle works
- [ ] Error handling works
- [ ] Service starts correctly after migration

## Rollout Plan

### Week 1: Implementation
- Days 1-3: Phase 1 (Core Implementation)
- Days 4-5: Phase 2 (Migration & Rollback)
- Day 6: Phase 3 (Enable by Default)
- Day 7: Testing & bug fixes

### Week 2: Rollout
- Day 1: Enable for internal testing
- Days 2-3: Enable for beta users
- Days 4-5: Enable by default for new installations
- Day 6: Monitor and fix issues
- Day 7: Full rollout

## Code Changes Summary

### New Files
1. `Sources/KeyPath/Managers/KanataDaemonManager.swift` (~200 lines)
2. `Resources/com.keypath.kanata.plist` (~30 lines)

### Modified Files
1. `Sources/KeyPath/Utilities/FeatureFlags.swift` (+5 lines)
2. `Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift` (+50 lines)
3. `Sources/KeyPath/UI/DiagnosticsView.swift` (+100 lines)

**Total:** ~385 lines of new/modified code

## Risk Assessment

### Low Risk
- Feature flag (can disable instantly)
- Dual path support (both work)
- Rollback available

### Medium Risk
- Migration logic (but tested)
- Service dependencies (but same as before)

### Mitigation
- Extensive testing before rollout
- Feature flag for quick disable
- Rollback always available
- Fallback to launchctl on error

## Success Criteria

- ✅ SMAppService registration works
- ✅ Migration from launchctl works
- ✅ Rollback to launchctl works
- ✅ New installations use SMAppService by default
- ✅ Existing installations can migrate
- ✅ No regressions in existing functionality

## Timeline

**Total: ~2 weeks**
- Week 1: Implementation (5-6 days)
- Week 2: Testing & Rollout (5-6 days)

## Next Steps

1. **Start Phase 1** - Create KanataDaemonManager
2. **Add Plist** - Create com.keypath.kanata.plist
3. **Integrate** - Update LaunchDaemonInstaller
4. **Test** - Test registration/unregistration
5. **Migrate** - Add migration logic
6. **Enable** - Make default for new installs

Let's ship it! 🚀

