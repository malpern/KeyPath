<details>
<summary>Helper Parity Plan</summary>

# Privileged Helper Parity Plan

Goal: eliminate AppleScript / Authorization Services code paths in the installer and rely exclusively on the SMJobBless helper. The table below maps each privileged behavior to its current implementation, the target helper RPC, and the tests that must be re-pointed once the helper owns the flow.

| Behavior | Current AppleScript/Authorization entry point | Target helper RPC / change | Tests to update once helper owns the path |
| --- | --- | --- | --- |
| Install Kanata + VHID services (fresh install) | `LaunchDaemonInstaller.executeAllWithAdminPrivileges` / `executeConsolidatedInstallationWithAuthServices` | Reuse `HelperProtocol.installLaunchDaemonServicesWithoutLoading` (or add `installAllServices`) to copy plists + bootstrap services; `PrivilegedOperationsCoordinator.installAllLaunchDaemonServices` should delegate to helper instead of `LaunchDaemonInstaller`. | `AuthorizationServicesSmokeTests`, `LaunchctlSmokeTests`, `InstallerEngineFunctionalTests` |
| Install VHID-only repair flow | `executeConsolidatedInstallationForVHIDOnly` (osascript) | Use existing `HelperProtocol.repairVHIDDaemonServices`. | `InstallerEngineFunctionalTests.testRepairFlow*`, `ServiceInstallGuardTests` |
| Restart unhealthy services / kickstart | `restartServicesWithAdmin` (osascript kickstart) | `HelperProtocol.restartUnhealthyServices` (already defined). | `PrivilegedOperationsCoordinatorTests.testRestartUnhealthyServicesIssuesKickstart` |
| Install log rotation service | `LaunchDaemonInstaller.installLogRotationService` (AdminCommandExecutor/osascript) | `HelperProtocol.installLogRotation`. Helper will own copying scripts + bootstrap. | `LogRotationTests`, `PrivilegedOperationsCoordinatorTests.testInstallLogRotationFailsOnCommandError` |
| Update TCP server configuration | `regenerateServiceConfiguration` uses `do shell script` | `HelperProtocol.regenerateServiceConfiguration`. | `PrivilegedOperationsCoordinatorTests` (add coverage when helper path is active) |
| Remove legacy helper artifacts | `HelperMaintenance.removeLegacyHelperArtifacts` (AdminCommandExecutor) | Add helper RPC (`removeLegacyHelperArtifacts`) so cleanup can occur without shell scripts. | `HelperMaintenanceTests` |
| Bundled Kanata binary install/restore | `BundledKanataManager` AppleScript copies | `HelperProtocol.installBundledKanataBinaryOnly` already exists—route Kanata manager through it. | `BundledKanataManager` unit tests (add) |
| Karabiner conflict auto-fixes | `KarabinerConflictService` AppleScript commands | Use `HelperProtocol.disableKarabinerGrabber` / `restartKarabinerDaemon`. | Conflict service tests (add coverage once helper path is live) |
| Wizard auto-fixer (system config writes) | `WizardAutoFixer` `do shell script "echo … > /usr/local/etc/…"` | New helper RPC (`writeSystemConfig(contents:path:)`) so auto-fixer never shells out. | `WizardAutoFixer` tests (add) |

## Migration Checklist
1. **Helper API audit** – confirm each required RPC exists or add it to `HelperProtocol` + helper implementation.
2. **Coordinator updates** – refactor `PrivilegedOperationsCoordinator` so every privileged behavior calls helper methods first and only falls back to AppleScript when `HelperManager` is unavailable (to be removed later).
3. **Test realignment** – point the AdminCommandExecutor-based tests (`PrivilegedOperationsCoordinatorTests`, `LogRotationTests`, `HelperMaintenanceTests`) at helper stubs instead of shell-command stubs to keep parity.
4. **Remove AppleScript** – once helper paths are stable and tests pass, delete the osascript codepaths from `LaunchDaemonInstaller`, `HelperMaintenance`, and other managers.

Documenting this mapping now ensures we know exactly which helper capabilities must exist before starting the refactor.

</details>
