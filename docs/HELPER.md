# Privileged Helper Implementation Plan

**Status:** Future Enhancement
**Priority:** Medium
**Estimated Effort:** 2-3 days
**Goal:** Professional user experience with zero contributor friction

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

### Phase 1: Extract Privileged Operations (1 day)

**Goal:** Centralize all privileged operations behind clean coordinator API.

**Tasks:**
- [ ] Create `PrivilegedOperationsCoordinator.swift`
- [ ] Define operation modes (helper vs sudo)
- [ ] Extract current sudo code to coordinator methods
- [ ] Update all callers to use coordinator (wizard, settings, etc.)
- [ ] Test: Verify all operations still work with direct sudo

**Files to modify:**
- `InstallationWizard/Core/LaunchDaemonInstaller.swift`
- `InstallationWizard/Core/WizardAutoFixer.swift`
- `Services/VHIDDeviceManager.swift`
- `Managers/KanataManager+Lifecycle.swift`

### Phase 2: Create Privileged Helper (1 day)

**Goal:** Implement helper target with XPC communication.

**Tasks:**
- [ ] Create `KeyPathHelper` target in Package.swift
- [ ] Implement `main.swift` (XPC listener setup)
- [ ] Implement `HelperService.swift` (root operations)
- [ ] Define `HelperProtocol.swift` (XPC interface)
- [ ] Create `HelperManager.swift` (app-side XPC connection)
- [ ] Implement SMJobBless() installation flow
- [ ] Add helper version checking

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
