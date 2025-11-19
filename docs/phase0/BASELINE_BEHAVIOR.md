# Baseline Behavior Documentation

**Status:** ✅ CAPTURED - Current behavior that must be preserved

**Date Captured:** 2025-11-17

**Purpose:** Document what existing code does so the façade can replicate it correctly

---

## Service Dependency Order

**Source:** `Tests/KeyPathTests/LaunchDaemonInstallerTests.swift`

**Critical Behavior:** Services MUST be installed in this exact order:

1. **VirtualHID Daemon** (`com.keypath.karabiner-vhiddaemon`) - FIRST
   - Provides the base VirtualHID framework
   - Other services depend on this

2. **VirtualHID Manager** (`com.keypath.karabiner-vhidmanager`) - SECOND
   - Manages VirtualHID devices
   - Depends on VirtualHID Daemon

3. **Kanata** (`com.keypath.kanata`) - LAST
   - Depends on both VirtualHID services being available
   - Will fail with "Input/output error" if VirtualHID services aren't running

**Failure if order violated:**
- `launchctl bootstrap` returns error code 5 (Input/output error)
- Services fail to start
- System services installation appears to fail to users

**Test Coverage:** `LaunchDaemonInstallerTests` verifies this order in:
- `executeConsolidatedInstallationWithAuthServices`
- `executeConsolidatedInstallationImproved`
- All inline script methods

**Must Preserve:** ✅ Façade must respect this order in `makePlan()` and `execute()`

---

## WizardAutoFixer Auto-Fix Action Mapping

**Source:** `Sources/KeyPath/InstallationWizard/Core/WizardAutoFixer.swift`

**Current Auto-Fix Actions:**
- `.installPrivilegedHelper` - Install helper tool
- `.reinstallPrivilegedHelper` - Reinstall helper
- `.terminateConflictingProcesses` - Kill conflicting processes
- `.startKarabinerDaemon` - Start Karabiner daemon
- `.restartVirtualHIDDaemon` - Restart VHID daemon
- `.installMissingComponents` - Install missing components
- `.createConfigDirectories` - Create config directories
- `.activateVHIDDeviceManager` - Activate VHID manager
- `.installLaunchDaemonServices` - Install LaunchDaemon services
- `.installBundledKanata` - Install bundled Kanata binary
- `.repairVHIDDaemonServices` - Repair VHID services
- `.synchronizeConfigPaths` - Sync config paths
- `.restartUnhealthyServices` - Restart unhealthy services
- `.adoptOrphanedProcess` - Adopt orphaned Kanata process
- `.replaceOrphanedProcess` - Replace orphaned process
- `.installLogRotation` - Install log rotation service
- `.replaceKanataWithBundled` - Replace Kanata with bundled version
- `.enableTCPServer` - Enable TCP server
- `.setupTCPAuthentication` - Setup TCP auth
- `.regenerateCommServiceConfiguration` - Regenerate comm config
- `.restartCommServer` - Restart comm server
- `.fixDriverVersionMismatch` - Fix driver version mismatch
- `.installCorrectVHIDDriver` - Install correct VHID driver

**Mapping to InstallIntent:**
- `.install` → Typically: install components, install services, install helper
- `.repair` → Typically: restart services, repair services, fix mismatches
- `.uninstall` → Typically: remove services, cleanup
- `.inspectOnly` → No auto-fix actions

**Must Preserve:** ✅ `makePlan()` must map intents to appropriate auto-fix actions

---

## PrivilegedOperationsCoordinator Fallback Chain

**Source:** `Sources/KeyPath/Core/PrivilegedOperationsCoordinator.swift`

**Operation Modes:**
- **DEBUG builds:** Always use `.directSudo` (AuthorizationExecuteWithPrivileges)
- **RELEASE builds:** Prefer `.privilegedHelper`, fall back to `.directSudo` on error

**Fallback Behavior:**
1. Try helper IPC first (if RELEASE)
2. If helper fails → Try Authorization Services
3. If Authorization Services fails → Try osascript/AppleScript
4. If all fail → Return error

**Example from code:**
```swift
// From downloadAndInstallCorrectVHIDDriver():
do {
    try await helperInstallCorrectDriver()
} catch {
    // Automatic fallback to sudo
    try await sudoInstallCorrectDriver()
}
```

**Must Preserve:** ✅ `PrivilegeBroker` must replicate this fallback chain

---

## SystemSnapshotAdapter Output Format

**Source:** `Sources/KeyPath/InstallationWizard/Core/SystemSnapshotAdapter.swift`

**Priority Order for State Determination:**
1. **Conflicts** (highest priority) → `.conflictsDetected`
2. **Kanata running** → `.active` (even if sub-components unhealthy)
3. **Missing permissions** → `.missingPermissions` (only if blocking)
4. **Missing components** → `.missingComponents`
5. **Daemon not running** → `.daemonNotRunning`
6. **Service not running** → `.serviceNotRunning` (everything ready but kanata not started)

**Key Logic:**
- Uses `isBlocking` (not `isReady`) for permissions - only marks as missing if DEFINITIVELY BLOCKED
- If Kanata is running → shows active regardless of sub-component health
- Only checks permissions if Kanata is NOT running

**Output Structure:**
```swift
SystemStateResult(
    state: WizardSystemState,  // One of the states above
    issues: [WizardIssue],     // List of detected issues
    autoFixActions: [AutoFixAction],  // Actions that can fix issues
    detectionTimestamp: Date
)
```

**Must Preserve:** ✅ `inspectSystem()` must produce similar output structure

---

## LaunchDaemonInstaller Service Creation

**Source:** `Sources/KeyPath/InstallationWizard/Core/LaunchDaemonInstaller.swift`

**Key Methods:**
- `createAllLaunchDaemonServices()` - Creates and installs all services
- `createKanataLaunchDaemon()` - Creates Kanata service via SMAppService
- `createVHIDDaemonService()` - Creates VHID daemon plist
- `createVHIDManagerService()` - Creates VHID manager plist
- `restartUnhealthyServices()` - Restarts services that are unhealthy

**SMAppService Guard:**
- Checks if SMAppService is active for Kanata
- If active → Skips Kanata plist creation (prevents reverting to launchctl)
- Only installs VirtualHID services via launchctl

**Version Checks:**
- `shouldUpgradeKanata()` - Checks if bundled version is newer than system version
- Compares versions using `--version` flag
- Returns true if upgrade needed

**Must Preserve:** ✅ `makePlan()` must generate recipes that replicate this logic

---

## Conflict Detection

**Source:** `dev-tools/test-updated-conflict.swift`

**Detection Logic:**
1. Use `pgrep -fl kanata-cmd` to find Kanata processes
2. For each PID, check if running as root using `ps -p <pid> -o user=`
3. If root-owned process found → Conflict detected
4. If any Kanata process found (even non-root) → Conflict detected

**Conflict Message:**
- "Found X Kanata process(es) running as root that need to be terminated"
- OR "Found X existing Kanata process(es) that need to be terminated"

**Must Preserve:** ✅ `inspectSystem()` must detect conflicts using similar logic

---

## SystemRequirements Compatibility Checks

**Source:** `Sources/KeyPath/InstallationWizard/Core/SystemRequirements.swift`

**macOS Version Detection:**
- `.modern` (≥11.x) - Uses DriverKit
- `.legacy` (≤10.x) - Uses kernel extension
- `.unknown` - Unknown version

**Driver Type:**
- Modern macOS → DriverKit VirtualHIDDevice (V5)
- Legacy macOS → Kernel Extension VirtualHIDDevice

**Compatibility Validation:**
- KeyPath requires macOS 14.0+
- Checks version compatibility
- Returns `ValidationResult` with issues and recommendations

**Must Preserve:** ✅ `inspectSystem()` must include compatibility info in SystemContext

---

## PrivilegedOperationsCoordinator Service Installation

**Source:** `Sources/KeyPath/Core/PrivilegedOperationsCoordinator.swift`

**Key Methods:**
- `installAllLaunchDaemonServices()` - Installs all services via SMAppService
- `restartUnhealthyServices()` - Restarts unhealthy services
- `installServicesIfUninstalled()` - Auto-installs if services missing
- `installLogRotation()` - Installs log rotation service
- `repairVHIDDaemonServices()` - Repairs VHID services

**Service Guard Logic:**
- Checks service state before operations
- Throttles auto-install attempts (30 second cooldown)
- Handles SMAppService pending state (notifies user)
- Removes legacy plists before migration

**Must Preserve:** ✅ `execute()` must use similar guard logic

---

## Summary: Critical Behaviors to Preserve

1. ✅ **Service dependency order:** VHID Daemon → VHID Manager → Kanata
2. ✅ **SMAppService guard:** Skip Kanata plist if SMAppService active
3. ✅ **Privilege fallback chain:** Helper → Auth Services → osascript
4. ✅ **State priority:** Conflicts → Kanata running → Permissions → Components
5. ✅ **Permission checking:** Use `isBlocking` not `isReady`
6. ✅ **Version checks:** Compare Kanata versions before upgrade
7. ✅ **Conflict detection:** Check for root-owned Kanata processes
8. ✅ **Service guard:** Throttle auto-installs, handle pending states

**All of these behaviors must be replicated in the façade.**


