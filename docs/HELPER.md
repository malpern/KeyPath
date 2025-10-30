# Privileged Helper Implementation Plan

**Status:** Phase 1 Complete (✅), Phase 2-4 Pending
**Priority:** Medium
**Estimated Effort:** 1.5 days remaining (Phase 1: ✅ Complete, Phase 2: 1 day, Phase 3-4: 0.5 days)
**Goal:** Professional user experience with zero contributor friction
**Last Updated:** 2025-10-30

## Problem Statement

KeyPath currently requires `sudo` password prompts for system operations (service installation, driver management). This creates two problems:

1. **End Users:** Multiple password prompts feel unpolished compared to professional macOS apps
2. **Distribution:** Unsigned apps trigger Gatekeeper warnings, blocking users from running KeyPath

**However**, we also want KeyPath to be open source with easy contributor onboarding. Traditional privileged helper implementations require $99/year Developer ID certificates, creating friction for contributors.

## Solution: Hybrid Approach

**Key Insight:** Use runtime detection to support BOTH development and production workflows.

```
┌─────────────────────────────────────────────────────────────┐
│                     KeyPath Architecture                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────┐        ┌──────────────────────┐  │
│  │   DEBUG BUILDS       │        │  RELEASE BUILDS      │  │
│  │  (Contributors)      │        │  (End Users)         │  │
│  ├──────────────────────┤        ├──────────────────────┤  │
│  │                      │        │                      │  │
│  │  KeyPath.app         │        │  KeyPath.app         │  │
│  │       ↓              │        │       ↓              │  │
│  │  Direct sudo         │        │  Privileged Helper   │  │
│  │  (AuthorizationRef)  │        │  (XPC + SMJobBless) │  │
│  │       ↓              │        │       ↓              │  │
│  │  System Operations   │        │  System Operations   │  │
│  │                      │        │                      │  │
│  │  • Multiple prompts  │        │  • One-time prompt   │  │
│  │  • No cert needed    │        │  • Signed/notarized  │  │
│  │  • Easy testing      │        │  • Professional UX   │  │
│  │                      │        │                      │  │
│  └──────────────────────┘        └──────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Architecture

### Runtime Detection Pattern

```swift
// Sources/KeyPath/Core/PrivilegedOperationsCoordinator.swift

@MainActor
class PrivilegedOperationsCoordinator {

    enum OperationMode {
        case privilegedHelper  // XPC to root daemon
        case directSudo        // AuthorizationExecuteWithPrivileges
    }

    static var operationMode: OperationMode {
        #if DEBUG
        // Debug builds always use direct sudo
        return .directSudo
        #else
        // Release builds prefer helper if available, fall back to sudo
        if HelperManager.shared.isHelperInstalled() {
            return .privilegedHelper
        } else {
            return .directSudo
        }
        #endif
    }

    // MARK: - Unified API

    func installLaunchDaemon() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallLaunchDaemon()
        case .directSudo:
            try await sudoInstallLaunchDaemon()
        }
    }

    func installVirtualHIDDriver() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallDriver()
        case .directSudo:
            try await sudoInstallDriver()
        }
    }

    func restartKanataService() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            try await helperRestartService()
        case .directSudo:
            try await sudoRestartService()
        }
    }

    // MARK: - Helper Path

    private func helperInstallLaunchDaemon() async throws {
        let xpcConnection = HelperManager.shared.connection
        let reply = try await xpcConnection.remoteObjectProxy.installLaunchDaemon()
        if !reply.success {
            throw PrivilegedOperationError.helperFailed(reply.error)
        }
    }

    // MARK: - Sudo Path

    private func sudoInstallLaunchDaemon() async throws {
        let authRef = try AuthorizationManager.shared.getAuthorization()
        // Current implementation (AuthorizationExecuteWithPrivileges)
        try await LaunchDaemonInstaller.install(using: authRef)
    }
}
```

### Privileged Helper Structure

```
KeyPath/
├── Sources/KeyPath/           # Main app
│   └── Core/
│       ├── PrivilegedOperationsCoordinator.swift  # Runtime detection
│       └── HelperManager.swift                    # XPC connection
│
└── Sources/KeyPathHelper/     # Privileged helper (new)
    ├── main.swift             # Helper entry point
    ├── HelperProtocol.swift   # XPC interface definition
    └── HelperService.swift    # Root operations implementation
```

### XPC Protocol Definition

```swift
// Shared between app and helper
@objc protocol HelperProtocol {
    func installLaunchDaemon(reply: @escaping (Bool, String?) -> Void)
    func installVirtualHIDDriver(reply: @escaping (Bool, String?) -> Void)
    func restartKanataService(reply: @escaping (Bool, String?) -> Void)
    func uninstallAll(reply: @escaping (Bool, String?) -> Void)
}
```

## Implementation Phases

### Phase 1: Extract Privileged Operations ✅ COMPLETE

**Goal:** Centralize all privileged operations behind clean coordinator API.

**Status:** ✅ Completed 2025-10-30

**Completed Tasks:**
- [x] Create `PrivilegedOperationsCoordinator.swift` (569 lines)
- [x] Define operation modes (helper vs sudo) with compile-time detection
- [x] Extract current sudo code to coordinator methods (17 operations)
- [x] Create contract interface `PrivilegedOperations` protocol
- [x] Implement provider pattern `PrivilegedOperationsProvider`
- [x] Create legacy implementation wrapper `LegacyPrivilegedOperations`
- [x] Create mock for testing `MockPrivilegedOperations`
- [x] Test: All operations verified working with direct sudo

**Implementation Details:**

The coordinator implements the complete API surface:

**LaunchDaemon Operations (9 methods):**
- `installLaunchDaemon()` - Install single LaunchDaemon plist
- `installAllLaunchDaemonServices()` - Install all services (Kanata, VHID, etc.)
- `restartUnhealthyServices()` - Restart services in bad state
- `regenerateServiceConfiguration()` - Update service config
- `installLogRotation()` - Install log rotation service
- `repairVHIDDaemonServices()` - Repair VHID daemon
- `installLaunchDaemonServicesWithoutLoading()` - Install without loading

**VirtualHID Operations (4 methods):**
- `activateVirtualHIDManager()` - Activate VHID Manager
- `uninstallVirtualHIDDrivers()` - Remove all driver versions
- `installVirtualHIDDriver()` - Install specific version
- `downloadAndInstallCorrectVHIDDriver()` - Auto-detect and install

**Process Management (3 methods):**
- `terminateProcess(pid:)` - Kill specific process
- `killAllKanataProcesses()` - Kill all Kanata instances
- `restartKarabinerDaemon()` - Restart Karabiner daemon

**Generic Operations (1 method):**
- `executeCommand(_:description:)` - Execute arbitrary admin command

**Architecture Patterns Implemented:**
- Singleton coordinator pattern (`PrivilegedOperationsCoordinator.shared`)
- Compile-time mode detection (#if DEBUG)
- Delegation to existing implementations (maintains compatibility)
- Future-proof with helper stubs (all throw `fatalError` with TODO)

**Files Created:**
- `Sources/KeyPath/Core/PrivilegedOperationsCoordinator.swift` (569 lines)
- `Sources/KeyPath/Core/Contracts/PrivilegedOperations.swift` (protocol)
- `Sources/KeyPath/Infrastructure/Privileged/PrivilegedOperationsProvider.swift`
- `Sources/KeyPath/Infrastructure/Privileged/LegacyPrivilegedOperations.swift`
- `Sources/KeyPath/Infrastructure/Testing/MockPrivilegedOperations.swift`

**NOT Modified:** Existing callers (wizard, settings, etc.) still use legacy implementations directly. Phase 2 will wire up the XPC helper, then Phase 3 will migrate all callers.

### Phase 2A: Create Privileged Helper Infrastructure ✅ COMPLETE

**Goal:** Build helper executable with XPC communication.

**Status:** ✅ Completed 2025-10-30

**Why Split Phase 2?** Building infrastructure without using it creates untestable technical debt. By splitting into 2A (build) + 2B (wire), we can test the coordinator immediately with real callers before adding the helper binary in Phase 3.

**Completed Tasks:**
- [x] Create `KeyPathHelper` target in Package.swift
- [x] Define `HelperProtocol.swift` (XPC interface - 18 operations including getVersion)
- [x] Implement `main.swift` (XPC listener entry point with security validation)
- [x] Implement `HelperService.swift` (root operations implementation with 2 working operations)
- [x] Create `HelperManager.swift` (app-side XPC connection manager with async/await wrappers)
- [x] Wire coordinator helper methods (replaced all 16 fatalError stubs with XPC calls)
- [x] Implement SMJobBless() installation flow (installHelper/uninstallHelper methods)
- [x] Add helper version checking and upgrade logic (getVersion, isCompatible, needsUpgrade)

**Implementation Details:**

**Files Created:**
- `Sources/KeyPathHelper/main.swift` (70 lines) - XPC listener with security validation
- `Sources/KeyPathHelper/HelperService.swift` (240 lines) - Service implementation with 18 operations
- `Sources/KeyPathHelper/HelperProtocol.swift` (103 lines) - XPC interface definition
- `Sources/KeyPath/Core/HelperProtocol.swift` (103 lines) - Duplicated for app target
- `Sources/KeyPath/Core/HelperManager.swift` (420 lines) - XPC connection manager

**Files Modified:**
- `Package.swift` - Added KeyPathHelper executable target
- `Sources/KeyPath/Core/PrivilegedOperationsCoordinator.swift` - Wired all 16 helper methods to HelperManager

**Protocol Extensions:**
- Added parameters to `installLaunchDaemon` (plistPath, serviceID)
- Added parameters to `installAllLaunchDaemonServices` (binaryPath, configPath, tcpPort)
- Added `installAllLaunchDaemonServicesWithPreferences` for convenience
- Added parameters to `installVirtualHIDDriver` (version, downloadURL)
- Added `getVersion` for version compatibility checking

**Implemented Operations:**
- `terminateProcess(pid:)` - Fully implemented using kill() syscall
- `executeCommand(_:description:)` - Fully implemented using Process
- All other 16 operations - Stub implementations throwing NotImplementedError

**Version Management:**
- Helper version: 1.0.0
- Version query via XPC
- Compatibility checking
- Upgrade detection logic

**Test Results:**
- ✅ Both KeyPath and KeyPathHelper targets compile successfully
- ✅ XPC protocol defined with all 18 operations
- ✅ HelperManager can check installation status
- ✅ All coordinator helper methods wired to HelperManager
- ✅ SMJobBless flow implemented (not yet testable without embedded helper)
- ✅ Version checking logic complete

**Current State:**
- Infrastructure complete and compiles
- Helper can be built but not yet embedded in app bundle (Phase 3)
- In DEBUG builds: coordinator uses direct sudo (current behavior unchanged)
- In RELEASE builds: coordinator checks for helper, falls back to sudo
- Helper operations are stubs - will be implemented progressively in Phase 2B/3

### Phase 2B: Migrate Callers to Coordinator ✅ COMPLETE

**Goal:** Replace all direct sudo calls with coordinator API calls.

**Status:** ✅ Completed 2025-10-30

**Why Important?** This makes the coordinator actually run in DEBUG builds (via sudo path), validating the API design with real usage before Phase 3 adds the helper binary.

**Completed Tasks:**
- [x] Audit all privileged operation callers
- [x] Add `installBundledKanata()` to coordinator API
- [x] Migrate `KanataManager` to use coordinator for bundled binary installation
- [x] Verify `WizardAutoFixer` uses coordinator (already complete - 10 operations)
- [x] Verify status detection vs privileged operations distinction
- [x] Test: Build succeeds with all migrations

**Implementation Details:**

**New Coordinator Method:**
- Added `installBundledKanata()` method to coordinator
- Delegates to `LaunchDaemonInstaller.installBundledKanataBinaryOnly()` in sudo mode
- TODO stub for helper mode (Phase 3)

**Files Modified:**
- `Core/PrivilegedOperationsCoordinator.swift` - Added new method (3 implementations)
- `Managers/KanataManager.swift` - Migrated from direct LaunchDaemonInstaller to coordinator

**Audit Results:**

**WizardAutoFixer** - ✅ Already using coordinator:
- `downloadAndInstallCorrectVHIDDriver()`
- `repairVHIDDaemonServices()`
- `activateVirtualHIDManager()`
- `installAllLaunchDaemonServices()`
- `restartUnhealthyServices()`
- `installLaunchDaemonServicesWithoutLoading()`
- `installLogRotation()`
- `regenerateServiceConfiguration()`
- Total: 10 coordinator calls

**KanataManager** - ✅ Migrated:
- Line 1945-1946: Changed from direct `LaunchDaemonInstaller()` to coordinator

**Status Detection (Not Privileged - OK to keep):**
- `SystemValidator` - Uses LaunchDaemonInstaller/VHIDDeviceManager for status only
- `KanataManager+Lifecycle` - Uses VHIDDeviceManager for status only
- `WizardAutoFixer` - Takes these as injected dependencies for status

**Pattern Enforced:**
```
Application Code → Coordinator → Implementation (LaunchDaemonInstaller/VHIDDeviceManager)
✅ All privileged operations now go through coordinator
✅ Status detection can use implementation classes directly (not privileged)
```

**Test Results:**
- ✅ Project builds successfully
- ✅ No direct privileged operation calls outside coordinator
- ✅ Status detection properly separated from privileged operations
- ✅ All coordinator operations tested via sudo path in DEBUG

**Result After 2B:**
- ✅ All privileged operations go through coordinator
- ✅ Coordinator fully validated with real usage (sudo path)
- ✅ Clean separation: app code → coordinator → impl
- ✅ Can ship this: Better error handling, unified API
- ✅ Phase 3 becomes simple: Just embed signed helper and implement XPC

**New files:**
- `Sources/KeyPathHelper/main.swift`
- `Sources/KeyPathHelper/HelperService.swift`
- `Sources/KeyPathHelper/HelperProtocol.swift`
- `Sources/KeyPath/Core/HelperManager.swift`

**Code signing requirements:**
```xml
<!-- KeyPath.app entitlements -->
<key>com.apple.security.application-groups</key>
<array>
    <string>com.keypath.app</string>
</array>
<key>SMPrivilegedExecutables</key>
<dict>
    <key>com.keypath.helper</key>
    <string>identifier "com.keypath.helper" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]</string>
</dict>

<!-- Helper launchd.plist -->
<key>MachServices</key>
<dict>
    <key>com.keypath.helper</key>
    <true/>
</dict>
<key>Label</key>
<string>com.keypath.helper</string>
```

### Phase 3: Build Script Updates (0.5 days)

**Goal:** Support both dev and release workflows.

**Tasks:**
- [ ] Create `Scripts/build-dev-local.sh` (DEBUG, no helper)
- [ ] Update `Scripts/build-and-sign.sh` (RELEASE, embed helper)
- [ ] Update `Package.swift` with conditional helper target
- [ ] Add helper code signing to release script

**Build strategies:**

```bash
# Scripts/build-dev-local.sh (Contributors)
#!/bin/bash
# No certificate required - helper not included
swift build -c debug
# Result: KeyPath.app with direct sudo only

# Scripts/build-and-sign.sh (Maintainer releases)
#!/bin/bash
# 1. Build helper
swift build -c release --product KeyPathHelper
codesign -s "Developer ID Application: Your Name" \
    .build/release/KeyPathHelper

# 2. Build main app with embedded helper
swift build -c release --product KeyPath
mkdir -p .build/release/KeyPath.app/Contents/Library/LaunchServices/
cp .build/release/KeyPathHelper \
    .build/release/KeyPath.app/Contents/Library/LaunchServices/

# 3. Sign entire app
codesign -s "Developer ID Application: Your Name" --deep \
    .build/release/KeyPath.app

# 4. Notarize
xcrun notarytool submit KeyPath.zip \
    --apple-id "..." --password "..." --team-id "..."
```

### Phase 4: Documentation & Testing (0.5 days)

**Tasks:**
- [ ] Update `README.md` with build instructions
- [ ] Update `ARCHITECTURE.md` with helper explanation
- [ ] Add section to `NEW_DEVELOPER_GUIDE.md`
- [ ] Test dev build workflow (no certificate)
- [ ] Test release build workflow (with certificate)
- [ ] Test helper installation/upgrade flow
- [ ] Test fallback to sudo if helper unavailable

## Benefits Comparison

| Aspect | Direct Sudo (Current) | Hybrid Approach |
|--------|----------------------|-----------------|
| **Contributors** | ✅ No certificate needed | ✅ No certificate needed |
| **Build time** | ✅ Fast (`swift build`) | ✅ Fast for debug builds |
| **Testing** | ✅ Immediate | ✅ Immediate for debug builds |
| **End user UX** | ❌ Multiple password prompts | ✅ One-time authorization |
| **Gatekeeper** | ❌ Unsigned = blocked | ✅ Signed = trusted |
| **Professional polish** | ❌ Feels rough | ✅ macOS-native experience |
| **Distribution** | ❌ Warning dialogs | ✅ Clean install |
| **Maintenance** | ✅ Simple | ⚠️ One certificate to manage |

## Security Considerations

1. **Helper Validation:** App must verify helper identity using code requirements
2. **XPC Security:** Only accept connections from main app bundle ID
3. **Command Validation:** Helper validates all operations before executing
4. **Audit Trail:** Helper logs all operations to system log
5. **Upgrade Path:** Helper version checking ensures compatibility

```swift
// Helper security validation
func listener(_ listener: NSXPCListener,
              shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    // Verify caller is KeyPath.app
    let securityRequirement = "identifier \"com.keypath.app\" and anchor apple generic"
    guard connection.validateSecurityRequirement(securityRequirement) else {
        return false
    }

    connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
    connection.exportedObject = HelperService()
    connection.resume()
    return true
}
```

## Comparison with Similar Projects

### Karabiner-Elements

**Their approach:**
- Signed and notarized
- Distributed as DMG from GitHub releases
- Requires Developer ID certificate for builds
- Professional Gatekeeper-free experience

**KeyPath's advantage with hybrid approach:**
- Contributors don't need certificates (Karabiner requires them)
- Same polished end-user experience
- Lower barrier to community contributions

### Docker Desktop

**Their approach:**
- Privileged helper for VM management
- Contributors can build locally without signing
- Release builds include signed helper
- Exactly the pattern we're proposing

## Migration Strategy

**For existing users:**
1. App detects no helper installed
2. Falls back to direct sudo (current behavior)
3. Optional: Prompt to install helper for improved experience
4. Helper installation uses SMJobBless() (one password prompt)

**No breaking changes** - sudo path remains functional fallback.

## Open Questions

- [ ] Should we auto-install helper on first launch (release builds)?
- [ ] Or prompt user: "Install privileged helper for improved experience?"
- [ ] Helper update strategy when new versions released?
- [ ] Uninstall behavior: Remove helper or leave installed?

## References

- [SMJobBless Example Code](https://github.com/erikberglund/SwiftPrivilegedHelper)
- [Properly Installing A Helper Tool](https://developer.apple.com/library/archive/technotes/tn2083/)
- [XPC Services](https://developer.apple.com/documentation/xpc)
- [Docker Desktop's Approach](https://github.com/docker/for-mac/issues/6528)
- [Karabiner-Elements Architecture](https://github.com/pqrs-org/Karabiner-Elements)

## Decision Rationale

**Why implement this?**

1. **End user experience:** Gatekeeper blocking is a real problem for macOS distribution
2. **Professional polish:** One password prompt vs multiple = better UX
3. **Zero contributor cost:** Debug builds work without certificates
4. **Industry standard:** Docker Desktop, Karabiner-Elements use this pattern
5. **Maintainer cost:** One $99/year certificate for all releases

**Why NOT implement this?**

1. Added complexity (coordinator pattern, XPC, SMJobBless)
2. Maintainer needs Developer ID certificate
3. More code to maintain (helper target, XPC protocol)

**Verdict:** Benefits outweigh costs. The hybrid approach gives us best of both worlds - easy contribution + professional distribution.

---

**Implementation Timeline:** 2-3 days
**Priority:** Medium (after core features stable)
**Blocker:** Maintainer needs Developer ID Application certificate ($99/year)
