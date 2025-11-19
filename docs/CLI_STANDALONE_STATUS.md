# Standalone CLI Status

## Current State

The CLI is currently **integrated** into the KeyPath app bundle. To enable a **standalone CLI** that can be used for installation, we need to move installer components to a shared library.

## What's Needed

To make `KeyPathCLI` executable work independently (for installation), these components need to be moved from `KeyPath` target to `KeyPathWizardCore`:

### Already Moved ✅
- `InstallerEngine.swift`
- `InstallerEngineTypes.swift`
- `PrivilegeBroker.swift`
- `SystemValidator.swift`
- `SystemRequirements.swift`
- `LaunchDaemonInstaller.swift`
- `VHIDDeviceManager.swift`
- `PrivilegedOperationsCoordinator.swift`
- `HelperManager.swift`
- `KanataBinaryDetector.swift`

### Still Need to Move/Fix ⚠️
- `HelperProtocol` (from KeyPathHelper target) - XPC protocol definition
- `CodeSigningStatus` (from KeyPath/KeyPathCore) - Code signing types
- `KanataDaemonManager` (from KeyPath target) - Service management state
- `SMAppServiceProtocol` (from KeyPath) - SMAppService abstraction

### Dependencies to Resolve
- `HelperManager` needs `HelperProtocol` (XPC interface)
- `KanataBinaryDetector` needs `CodeSigningStatus`
- `PrivilegedOperationsCoordinator` needs `KanataDaemonManager`

## Current Workaround

**Use the integrated CLI** (works now):
```bash
# Build KeyPath
swift build --target KeyPath

# Run CLI from build directory (may have timing issues)
.build/arm64-apple-macosx/debug/KeyPath install

# Or use installed app bundle (recommended)
/Applications/KeyPath.app/Contents/MacOS/KeyPath install
```

## Next Steps

1. Move `HelperProtocol` to KeyPathCore or create protocol file in KeyPathWizardCore
2. Move `CodeSigningStatus` to KeyPathCore (if not already there)
3. Move `KanataDaemonManager` to KeyPathWizardCore or make it optional
4. Move `SMAppServiceProtocol` to KeyPathWizardCore
5. Update all imports
6. Test standalone CLI build

## Alternative: Fix Integrated CLI Timing

Instead of standalone CLI, we could fix the SwiftUI initialization timing issue so the integrated CLI works reliably from the build directory. This would be simpler and achieve the same goal.


