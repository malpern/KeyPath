# Task: Extract PlistGenerator from LaunchDaemonInstaller

## Goal
Extract all plist generation functions from `LaunchDaemonInstaller.swift` into a new standalone service called `PlistGenerator.swift`. This is an extraction-only task - you will NOT modify LaunchDaemonInstaller.swift.

## Git Workflow
1. Create a new branch: `git checkout -b refactor/extract-plist-generator`
2. Make your changes and commit with clear messages
3. Push your branch: `git push -u origin refactor/extract-plist-generator`
4. When complete, run `swift build` and `swift test` to verify everything works
5. Commit the final working state and push

## Files to Read First
- Sources/KeyPathAppKit/InstallationWizard/Core/LaunchDaemonInstaller.swift
  - Lines 930-1043: plist generation methods
  - Lines 2771-2800: log rotation plist
  - Lines 2697-2722: argument building
  - Lines 29-88: constants (service IDs, paths)
- Sources/KeyPathHelper/HelperService.swift (lines 649-840 - has duplicate plist generation for reference)

## What to Create
Create `Sources/KeyPathAppKit/InstallationWizard/Core/PlistGenerator.swift` containing:

```swift
import Foundation
import KeyPathCore

/// Generates launchd plist XML content for KeyPath services.
/// Pure functions with no side effects - just string generation.
struct PlistGenerator {
    
    // Service identifiers (copy from LaunchDaemonInstaller constants)
    static let kanataServiceID = "com.keypath.kanata"
    static let vhidDaemonServiceID = "org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon"
    static let vhidManagerServiceID = "org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Manager"
    
    // Paths (copy from LaunchDaemonInstaller constants)
    static let vhidDaemonPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    static let vhidManagerPath = "/Applications/Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    
    /// Generate Kanata service plist
    static func generateKanataPlist(binaryPath: String, configPath: String, tcpPort: Int = 37001) -> String
    
    /// Generate VHID Daemon plist
    static func generateVHIDDaemonPlist() -> String
    
    /// Generate VHID Manager plist  
    static func generateVHIDManagerPlist() -> String
    
    /// Generate log rotation plist
    static func generateLogRotationPlist(scriptPath: String) -> String
    
    /// Build Kanata program arguments array
    static func buildKanataPlistArguments(binaryPath: String, configPath: String, tcpPort: Int = 37001) -> [String]
}
```

## Requirements
- Make it a struct with static methods (pure functions, no state)
- Copy the exact plist XML from LaunchDaemonInstaller - do NOT change any XML content
- Include the service ID and path constants in the new file
- Add documentation comments explaining each plist's purpose
- Import `Foundation` and `KeyPathCore`

## Do NOT
- Modify LaunchDaemonInstaller.swift (integration will be done separately)
- Modify HelperService.swift
- Change any plist content/format - copy exactly
- Touch RuntimeCoordinator or any UI files
- Add new external dependencies

## Verification
After creating the file:
1. Run `swift build` - must succeed with no errors
2. Run `swift test` - all tests must pass
3. The new file should compile independently

## Success Criteria
- New file `Sources/KeyPathAppKit/InstallationWizard/Core/PlistGenerator.swift` exists
- Contains all 5 functions with correct implementations
- `swift build` succeeds
- `swift test` passes
- Branch pushed to origin

