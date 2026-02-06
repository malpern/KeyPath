import Foundation
import KeyPathCore

/// Coordinates installation operations
@MainActor
final class InstallationCoordinator {
    // MARK: - Initialization

    init() {}

    // MARK: - First-Time Install Detection

    func isFirstTimeInstall(configPath: String) -> Bool {
        // Check if Kanata binary is installed (considers SMAppService vs launchctl)
        let detector = KanataBinaryDetector.shared
        let isInstalled = detector.isInstalled()

        if !isInstalled {
            AppLogger.shared.log("🆕 [InstallCoordinator] Kanata binary not installed - fresh install detected")
            return true
        }

        // Check for user config file
        let hasUserConfig = FileManager.default.fileExists(atPath: configPath)

        if !hasUserConfig {
            AppLogger.shared.log("🆕 [InstallCoordinator] No user config found at \(configPath) - fresh install detected")
            return true
        }

        AppLogger.shared.info("✅ [InstallCoordinator] Both Kanata binary and user config exist - returning user")
        return false
    }

    // MARK: - Installation Progress

    /// Installation step result
    struct StepResult {
        let stepNumber: Int
        let totalSteps: Int
        let success: Bool
        let warning: Bool
    }

    /// Check if Kanata binary is available
    func checkKanataBinary(stepNumber: Int = 1, totalSteps: Int = 5) -> StepResult {
        AppLogger.shared.log("🔧 [Installation] Step \(stepNumber)/\(totalSteps): Checking/installing Kanata binary...")

        let detector = KanataBinaryDetector.shared

        if detector.isInstalled() {
            AppLogger.shared.log(
                "✅ [Installation] Step \(stepNumber) SUCCESS: Kanata binary ready at /Library/KeyPath/bin/kanata"
            )
            return StepResult(stepNumber: stepNumber, totalSteps: totalSteps, success: true, warning: false)
        } else {
            AppLogger.shared.log(
                "⚠️ [Installation] Step \(stepNumber) WARNING: Kanata system binary missing at /Library/KeyPath/bin/kanata"
            )
            return StepResult(stepNumber: stepNumber, totalSteps: totalSteps, success: false, warning: true)
        }
    }

    /// Check if Karabiner driver is installed
    func checkKarabinerDriver(stepNumber: Int = 2, totalSteps: Int = 5) -> StepResult {
        AppLogger.shared.log("🔧 [Installation] Step \(stepNumber)/\(totalSteps): Checking Karabiner driver...")

        let driverPath = KeyPathConstants.VirtualHID.driverPath
        if !FileManager.default.fileExists(atPath: driverPath) {
            AppLogger.shared.log("⚠️ [Installation] Step \(stepNumber) WARNING: Karabiner driver not found at \(driverPath)")
            AppLogger.shared.log("ℹ️ [Installation] User should install Karabiner-Elements first")
            return StepResult(stepNumber: stepNumber, totalSteps: totalSteps, success: true, warning: true)
        } else {
            AppLogger.shared.log("✅ [Installation] Step \(stepNumber) SUCCESS: Karabiner driver verified at \(driverPath)")
            return StepResult(stepNumber: stepNumber, totalSteps: totalSteps, success: true, warning: false)
        }
    }

    /// Log daemon directories step
    func logDaemonDirectoriesStep(stepNumber: Int = 3, totalSteps: Int = 5) {
        AppLogger.shared.log("🔧 [Installation] Step \(stepNumber)/\(totalSteps): Preparing daemon directories...")
    }

    func logDaemonDirectoriesSuccess(stepNumber: Int = 3, totalSteps _: Int = 5) {
        AppLogger.shared.info("✅ [Installation] Step \(stepNumber) SUCCESS: Daemon directories prepared")
    }

    /// Check config file step
    func checkConfigFile(configPath: String, stepNumber: Int = 4, totalSteps: Int = 5) -> StepResult {
        AppLogger.shared.log("🔧 [Installation] Step \(stepNumber)/\(totalSteps): Creating user configuration...")

        if FileManager.default.fileExists(atPath: configPath) {
            AppLogger.shared.log("✅ [Installation] Step \(stepNumber) SUCCESS: User config available at \(configPath)")
            return StepResult(stepNumber: stepNumber, totalSteps: totalSteps, success: true, warning: false)
        } else {
            AppLogger.shared.error("❌ [Installation] Step \(stepNumber) FAILED: User config missing at \(configPath)")
            return StepResult(stepNumber: stepNumber, totalSteps: totalSteps, success: false, warning: false)
        }
    }

    /// Log system config step (skipped in new architecture)
    func logSystemConfigSkipped(stepNumber: Int = 5, totalSteps: Int = 5) {
        AppLogger.shared.log("🔧 [Installation] Step \(stepNumber)/\(totalSteps): System config step skipped - LaunchDaemon uses user config directly")
        AppLogger.shared.info("✅ [Installation] Step \(stepNumber) SUCCESS: Using ~/.config/keypath path directly")
    }

    /// Log installation result
    func logInstallationResult(stepsCompleted: Int, stepsFailed: Int, totalSteps: Int) -> Bool {
        let success = stepsCompleted >= 4 // Require at least user config + binary + directories

        if success {
            AppLogger.shared.log("✅ [InstallCoordinator] Installation completed successfully (\(stepsCompleted)/\(totalSteps) steps completed)")
        } else {
            AppLogger.shared.log("❌ [InstallCoordinator] Installation failed (\(stepsFailed) steps failed, only \(stepsCompleted)/\(totalSteps) completed)")
        }

        return success
    }

    // MARK: - Daemon Directory Preparation

    func prepareDaemonDirectories() async {
        AppLogger.shared.log("🔧 [InstallCoordinator] Preparing Karabiner daemon directories...")

        // The daemon needs access to rootOnlyTmp
        let rootOnlyPath = KeyPathConstants.VirtualHID.rootOnlyTmp
        let tmpPath = KeyPathConstants.VirtualHID.tmpDir

        // Use AppleScript to run commands with admin privileges
        let createDirScript = """
        do shell script "mkdir -p '\(rootOnlyPath)' && chown -R \(NSUserName()) '\(tmpPath)' && chmod -R 755 '\(tmpPath)'"
        with administrator privileges
        with prompt "KeyPath needs to prepare system directories for the virtual keyboard."
        """

        do {
            let result = try await SubprocessRunner.shared.run(
                KeyPathConstants.System.osascript,
                args: ["-e", createDirScript],
                timeout: 30
            )

            if result.exitCode == 0 {
                AppLogger.shared.info("✅ [InstallCoordinator] Successfully prepared daemon directories")
                await prepareLogDirectories()
            } else {
                AppLogger.shared.error("❌ [InstallCoordinator] Failed to prepare directories: \(result.stderr)")
            }
        } catch {
            AppLogger.shared.error("❌ [InstallCoordinator] Error preparing daemon directories: \(error)")
        }
    }

    private func prepareLogDirectories() async {
        let karabinerLogDir = KeyPathConstants.Logs.karabinerDir
        let logDirScript =
            "do shell script \"mkdir -p '\(karabinerLogDir)' && chmod 755 '\(karabinerLogDir)'\" with administrator privileges with prompt \"KeyPath needs to create system log directories.\""

        do {
            let result = try await SubprocessRunner.shared.run(
                KeyPathConstants.System.osascript,
                args: ["-e", logDirScript],
                timeout: 30
            )

            if result.exitCode == 0 {
                AppLogger.shared.info("✅ [InstallCoordinator] Log directory permissions set")
            } else {
                AppLogger.shared.warn("⚠️ [InstallCoordinator] Could not set log directory permissions")
            }
        } catch {
            AppLogger.shared.warn("⚠️ [InstallCoordinator] Error preparing log directories: \(error)")
        }
    }
}
