# Task: Extract PrivilegedExecutor from LaunchDaemonInstaller

## Goal
Extract all privileged execution utilities (sudo, osascript, admin prompts) from `LaunchDaemonInstaller.swift` into a new service called `PrivilegedExecutor.swift`. This is an extraction-only task - you will NOT modify LaunchDaemonInstaller.swift.

## Git Workflow
1. Create a new branch: `git checkout -b refactor/extract-privileged-executor`
2. Make your changes and commit with clear messages
3. Push your branch: `git push -u origin refactor/extract-privileged-executor`
4. When complete, run `swift build` and `swift test` to verify everything works
5. Commit the final working state and push

## Files to Read First
- Sources/KeyPathAppKit/InstallationWizard/Core/LaunchDaemonInstaller.swift
  - Lines 232-310: `executeWithPrivileges()`, `executeWithSudo()`, `executeWithOsascript()`
  - Lines 99-175: `testAdminDialog()`, `executeOSAScriptDirectly()`, `executeOSAScriptOnMainThread()`
  - Lines 226-230: `escapeForAppleScript()`
- Sources/KeyPathCore/TestEnvironment.swift (for `useSudoForPrivilegedOps` and `skipAdminOperations`)
- Sources/KeyPathCore/PrivilegedCommandRunner.swift (related code, may have overlap)

## What to Create
Create `Sources/KeyPathAppKit/InstallationWizard/Core/PrivilegedExecutor.swift` containing:

```swift
import Foundation
import KeyPathCore

/// Handles privileged command execution via sudo or osascript.
/// Provides a unified interface for operations requiring admin rights.
///
/// Two execution modes:
/// 1. `sudo -n` (non-interactive) - used when KEYPATH_USE_SUDO=1 is set (dev/test)
/// 2. `osascript` with admin dialog - used in production for user-facing prompts
final class PrivilegedExecutor {
    
    static let shared = PrivilegedExecutor()
    
    private init() {}
    
    /// Execute command with appropriate privilege escalation (sudo or osascript)
    /// Automatically chooses based on TestEnvironment.useSudoForPrivilegedOps
    func executeWithPrivileges(command: String, prompt: String) -> (success: Bool, output: String)
    
    /// Execute command with sudo -n (non-interactive, requires sudoers setup)
    func executeWithSudo(command: String) -> (success: Bool, output: String)
    
    /// Execute command with osascript admin dialog
    func executeWithOsascript(command: String, prompt: String) -> (success: Bool, output: String)
    
    /// Test if admin dialog can be shown (useful for pre-flight checks)
    func testAdminDialog() -> Bool
    
    /// Escape string for safe use in AppleScript
    func escapeForAppleScript(_ command: String) -> String
}
```

## Requirements
- Make it a final class with a shared singleton
- Check `TestEnvironment.useSudoForPrivilegedOps` to choose sudo vs osascript
- Check `TestEnvironment.skipAdminOperations` for test mode (return early with success)
- Include proper logging with `AppLogger.shared.log()`
- Document which methods may block on main thread (osascript dialogs)
- Copy the exact logic from LaunchDaemonInstaller - preserve all edge cases

## Important Context
The codebase uses two privilege escalation methods:
1. **`sudo -n`** (non-interactive) - used when `KEYPATH_USE_SUDO=1` env var is set (dev/test)
2. **`osascript`** with admin dialog - used in production for user-facing prompts

The new service MUST preserve this dual-path behavior. The choice is made by checking:
```swift
TestEnvironment.useSudoForPrivilegedOps  // true = use sudo, false = use osascript
```

## Do NOT
- Modify LaunchDaemonInstaller.swift (integration will be done separately)
- Change the actual privilege escalation behavior
- Modify how sudo vs osascript is chosen
- Touch RuntimeCoordinator or UI files
- Change the TestEnvironment integration

## Verification
After creating the file:
1. Run `swift build` - must succeed with no errors
2. Run `swift test` - all tests must pass
3. The new file should compile independently

## Success Criteria
- New file `Sources/KeyPathAppKit/InstallationWizard/Core/PrivilegedExecutor.swift` exists
- Contains all 5 functions with correct implementations copied from LaunchDaemonInstaller
- Preserves dual-path (sudo/osascript) behavior
- `swift build` succeeds
- `swift test` passes
- Branch pushed to origin

