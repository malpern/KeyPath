# Task: Extract KanataBinaryInstaller from LaunchDaemonInstaller

## Goal
Extract kanata binary installation logic from `LaunchDaemonInstaller.swift` into a new service called `KanataBinaryInstaller.swift`. This is an extraction-only task - you will NOT modify LaunchDaemonInstaller.swift.

## Git Workflow
1. Create a new branch: `git checkout -b refactor/extract-binary-installer`
2. Make your changes and commit with clear messages
3. Push your branch: `git push -u origin refactor/extract-binary-installer`
4. When complete, run `swift build` and `swift test` to verify everything works
5. Commit the final working state and push

## Files to Read First
- Sources/KeyPathAppKit/InstallationWizard/Core/LaunchDaemonInstaller.swift
  - Lines 2912-3000: `installBundledKanataBinaryOnly()` 
  - Lines 342-405: `shouldUpgradeKanata()`, `getKanataVersionAtPath()`
  - Lines 315-340: `getKanataBinaryPath()`
- Sources/KeyPathCore/WizardSystemPaths.swift (for path constants)
- Sources/KeyPathCore/TestEnvironment.swift (for test mode checks)
- Sources/KeyPathCore/Logger.swift (for AppLogger usage)

## What to Create
Create `Sources/KeyPathAppKit/InstallationWizard/Core/KanataBinaryInstaller.swift` containing:

```swift
import Foundation
import KeyPathCore

/// Handles installation and management of the Kanata binary.
/// Responsible for copying bundled binary to system location and version checks.
final class KanataBinaryInstaller {
    
    static let shared = KanataBinaryInstaller()
    
    private init() {}
    
    /// Install bundled Kanata binary to system location (/Library/KeyPath/bin/kanata)
    /// Returns true if installation succeeded or binary already exists
    func installBundledKanata() -> Bool
    
    /// Check if bundled Kanata should upgrade the system installation
    func shouldUpgradeKanata() -> Bool
    
    /// Extract version string from Kanata binary at path
    func getKanataVersionAtPath(_ path: String) -> String?
    
    /// Get the appropriate Kanata binary path (system or bundled)
    func getKanataBinaryPath() -> String
    
    /// Check if bundled Kanata binary exists in app bundle
    func isBundledKanataAvailable() -> Bool
}
```

## Requirements
- Make it a final class with a shared singleton
- Use `WizardSystemPaths.bundledKanataPath` and `WizardSystemPaths.kanataSystemInstallPath`
- Check `TestEnvironment.skipAdminOperations` for test mode
- Include proper logging with `AppLogger.shared.log()`
- The install function needs to execute privileged commands (copy to /Library requires admin)
- Copy the exact logic from LaunchDaemonInstaller - preserve all edge cases and error handling

## Key Paths (from WizardSystemPaths)
```swift
WizardSystemPaths.bundledKanataPath      // App bundle location
WizardSystemPaths.kanataSystemInstallPath // /Library/KeyPath/bin/kanata
```

## Do NOT
- Modify LaunchDaemonInstaller.swift (integration will be done separately)
- Change the actual installation logic or paths
- Modify the privilege escalation mechanism (just copy it)
- Touch RuntimeCoordinator or UI files
- Change how the binary is signed or verified

## Verification
After creating the file:
1. Run `swift build` - must succeed with no errors
2. Run `swift test` - all tests must pass
3. The new file should compile independently

## Success Criteria
- New file `Sources/KeyPathAppKit/InstallationWizard/Core/KanataBinaryInstaller.swift` exists
- Contains all 5 functions with correct implementations copied from LaunchDaemonInstaller
- `swift build` succeeds
- `swift test` passes
- Branch pushed to origin

