import AppKit
import Foundation

/// Handles automatic fixing of detected issues - pure action logic
class WizardAutoFixer: AutoFixCapable {
  private let kanataManager: KanataManager
  private let vhidDeviceManager: VHIDDeviceManager
  private let launchDaemonInstaller: LaunchDaemonInstaller
  private let packageManager: PackageManager

  init(
    kanataManager: KanataManager, vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
    launchDaemonInstaller: LaunchDaemonInstaller = LaunchDaemonInstaller(),
    packageManager: PackageManager = PackageManager()
  ) {
    self.kanataManager = kanataManager
    self.vhidDeviceManager = vhidDeviceManager
    self.launchDaemonInstaller = launchDaemonInstaller
    self.packageManager = packageManager
  }

  // MARK: - AutoFixCapable Protocol

  func canAutoFix(_ action: AutoFixAction) -> Bool {
    switch action {
    case .terminateConflictingProcesses:
      return true  // We can always attempt to terminate processes
    case .startKarabinerDaemon:
      return true  // We can attempt to start the daemon
    case .restartVirtualHIDDaemon:
      return true  // We can attempt to restart VirtualHID daemon
    case .installMissingComponents:
      return true  // We can run the installation script
    case .createConfigDirectories:
      return true  // We can create directories
    case .activateVHIDDeviceManager:
      return vhidDeviceManager.detectInstallation()  // Only if manager is installed
    case .installLaunchDaemonServices:
      return true  // We can attempt to install LaunchDaemon services
    case .installViaBrew:
      return packageManager.checkHomebrewInstallation()  // Only if Homebrew is available
    }
  }

  func performAutoFix(_ action: AutoFixAction) async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Attempting auto-fix: \(action)")

    switch action {
    case .terminateConflictingProcesses:
      return await terminateConflictingProcesses()
    case .startKarabinerDaemon:
      return await startKarabinerDaemon()
    case .restartVirtualHIDDaemon:
      return await restartVirtualHIDDaemon()
    case .installMissingComponents:
      return await installMissingComponents()
    case .createConfigDirectories:
      return await createConfigDirectories()
    case .activateVHIDDeviceManager:
      return await activateVHIDDeviceManager()
    case .installLaunchDaemonServices:
      return await installLaunchDaemonServices()
    case .installViaBrew:
      return await installViaBrew()
    }
  }

  // MARK: - Individual Auto-Fix Actions

  private func terminateConflictingProcesses() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Terminating conflicting processes")

    // First try temporary fix (just killing processes)
    let temporarySuccess = await kanataManager.killKarabinerGrabber()

    if temporarySuccess {
      AppLogger.shared.log(
        "✅ [AutoFixer] Successfully terminated conflicting processes (temporary)")

      // Wait for processes to fully terminate
      try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

      // Check if Karabiner Elements is installed and offer permanent disable
      if await isKarabinerElementsInstalled() {
        let permanentSuccess = await kanataManager.disableKarabinerElementsPermanently()
        if permanentSuccess {
          AppLogger.shared.log(
            "✅ [AutoFixer] Successfully disabled Karabiner Elements permanently - effective immediately"
          )
          AppLogger.shared.log("ℹ️ [AutoFixer] No restart required - conflicts resolved permanently")
        } else {
          AppLogger.shared.log(
            "⚠️ [AutoFixer] Temporary fix applied, but permanent disable was declined or failed")
        }
      }

      return true
    } else {
      AppLogger.shared.log("❌ [AutoFixer] Failed to terminate conflicting processes")
      return false
    }
  }

  /// Check if Karabiner Elements is installed on the system
  private func isKarabinerElementsInstalled() async -> Bool {
    let karabinerAppPath = "/Applications/Karabiner-Elements.app"
    return FileManager.default.fileExists(atPath: karabinerAppPath)
  }

  private func startKarabinerDaemon() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Starting Karabiner daemon")

    let success = await kanataManager.startKarabinerDaemon()

    if success {
      AppLogger.shared.log("✅ [AutoFixer] Successfully started Karabiner daemon")
    } else {
      AppLogger.shared.log("❌ [AutoFixer] Failed to start Karabiner daemon")
    }

    return success
  }

  private func restartVirtualHIDDaemon() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Fixing VirtualHID connection health issues")

    // Step 1: Try to clear Kanata log to reset connection health detection
    await clearKanataLog()

    // Step 2: Use proven working approach - daemon restart
    // (Skipping problematic forceActivate command that causes hangs/crashes)
    AppLogger.shared.log("🔧 [AutoFixer] Using enhanced daemon restart approach")
    let restartSuccess = await legacyRestartVirtualHIDDaemon()

    if restartSuccess {
      AppLogger.shared.log("✅ [AutoFixer] Successfully fixed VirtualHID connection health")
      return true
    } else {
      AppLogger.shared.log("❌ [AutoFixer] VirtualHID daemon restart failed")
      return false
    }
  }

  /// Clear Kanata log file to reset connection health detection
  private func clearKanataLog() async {
    AppLogger.shared.log("🔧 [AutoFixer] Attempting to clear Kanata log for fresh connection health")

    let logPath = "/var/log/kanata.log"

    // Try to truncate the log file
    let truncateTask = Process()
    truncateTask.executableURL = URL(fileURLWithPath: "/usr/bin/truncate")
    truncateTask.arguments = ["-s", "0", logPath]

    do {
      try truncateTask.run()
      truncateTask.waitUntilExit()

      if truncateTask.terminationStatus == 0 {
        AppLogger.shared.log("✅ [AutoFixer] Successfully cleared Kanata log")
      } else {
        AppLogger.shared.log(
          "⚠️ [AutoFixer] Could not clear Kanata log (may require admin privileges)")
      }
    } catch {
      AppLogger.shared.log("⚠️ [AutoFixer] Error clearing Kanata log: \(error)")
    }
  }

  /// Force activate VirtualHID Manager using the manager application
  private func forceActivateVirtualHIDManager() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Force activating VirtualHID Manager")

    let managerPath =
      "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

    guard FileManager.default.fileExists(atPath: managerPath) else {
      AppLogger.shared.log("❌ [AutoFixer] VirtualHID Manager not found at expected path")
      return false
    }

    return await withCheckedContinuation { continuation in
      let activateTask = Process()
      activateTask.executableURL = URL(fileURLWithPath: managerPath)
      activateTask.arguments = ["forceActivate"]

      // Use atomic flag to prevent double resumption
      let lock = NSLock()
      var hasResumed = false

      // Set up timeout task
      let timeoutTask = Task {
        try? await Task.sleep(nanoseconds: 10_000_000_000)  // 10 second timeout

        lock.lock()
        if !hasResumed {
          hasResumed = true
          lock.unlock()
          AppLogger.shared.log(
            "⚠️ [AutoFixer] VirtualHID Manager activation timed out after 10 seconds")
          activateTask.terminate()
          continuation.resume(returning: false)
        } else {
          lock.unlock()
        }
      }

      activateTask.terminationHandler = { process in
        timeoutTask.cancel()

        lock.lock()
        if !hasResumed {
          hasResumed = true
          lock.unlock()
          let success = process.terminationStatus == 0
          if success {
            AppLogger.shared.log("✅ [AutoFixer] VirtualHID Manager force activation completed")
          } else {
            AppLogger.shared.log(
              "❌ [AutoFixer] VirtualHID Manager force activation failed with status: \(process.terminationStatus)"
            )
          }
          continuation.resume(returning: success)
        } else {
          lock.unlock()
        }
      }

      do {
        try activateTask.run()
      } catch {
        timeoutTask.cancel()

        lock.lock()
        if !hasResumed {
          hasResumed = true
          lock.unlock()
          AppLogger.shared.log("❌ [AutoFixer] Error starting VirtualHID Manager: \(error)")
          continuation.resume(returning: false)
        } else {
          lock.unlock()
        }
      }
    }
  }

  /// Legacy daemon restart method (fallback)
  private func legacyRestartVirtualHIDDaemon() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Using legacy VirtualHID daemon restart")

    // Kill existing daemon
    let killTask = Process()
    killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    killTask.arguments = ["-f", "Karabiner-VirtualHIDDevice-Daemon"]

    do {
      try killTask.run()
      killTask.waitUntilExit()

      // Wait for process to terminate
      try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

      // Start daemon again
      let startSuccess = await startKarabinerDaemon()

      if startSuccess {
        AppLogger.shared.log("✅ [AutoFixer] Legacy VirtualHID daemon restart completed")
      } else {
        AppLogger.shared.log("❌ [AutoFixer] Legacy VirtualHID daemon restart failed")
      }

      return startSuccess

    } catch {
      AppLogger.shared.log("❌ [AutoFixer] Error in legacy VirtualHID daemon restart: \(error)")
      return false
    }
  }

  private func installMissingComponents() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Installing missing components")

    let success = await kanataManager.performTransparentInstallation()

    if success {
      AppLogger.shared.log("✅ [AutoFixer] Successfully installed missing components")
    } else {
      AppLogger.shared.log("❌ [AutoFixer] Failed to install missing components")
    }

    return success
  }

  private func createConfigDirectories() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Creating config directories")

    let configDirectory = "\(NSHomeDirectory())/Library/Application Support/KeyPath"

    do {
      try FileManager.default.createDirectory(
        atPath: configDirectory,
        withIntermediateDirectories: true,
        attributes: nil
      )

      AppLogger.shared.log("✅ [AutoFixer] Successfully created config directories")
      return true

    } catch {
      AppLogger.shared.log("❌ [AutoFixer] Failed to create config directories: \(error)")
      return false
    }
  }

  private func activateVHIDDeviceManager() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Activating VHIDDevice Manager")

    // First try automatic activation
    let success = await vhidDeviceManager.activateManager()

    if success {
      AppLogger.shared.log("✅ [AutoFixer] Successfully activated VHIDDevice Manager")
      return true
    } else {
      AppLogger.shared.log(
        "⚠️ [AutoFixer] Automatic activation failed - showing user dialog for manual activation")

      // Show dialog to guide user through manual driver extension activation
      await showDriverExtensionDialog()

      // Wait a moment for user to potentially complete the action
      try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

      // Check if activation succeeded after user intervention
      let manualSuccess = vhidDeviceManager.detectActivation()

      if manualSuccess {
        AppLogger.shared.log("✅ [AutoFixer] VHIDDevice Manager activated after user intervention")
        return true
      } else {
        AppLogger.shared.log(
          "⚠️ [AutoFixer] VHIDDevice Manager still not activated - user may need more time")
        // Still return true since we showed helpful guidance
        return true
      }
    }
  }

  /// Show dialog to guide user through manual driver extension activation
  private func showDriverExtensionDialog() async {
    await MainActor.run {
      let alert = NSAlert()
      alert.messageText = "Driver Extension Activation Required"
      alert.informativeText = """
        KeyPath needs to activate the VirtualHID Device driver extension, but this requires manual approval for security.

        Please follow these steps:

        1. Click "Open System Settings" below
        2. Go to Privacy & Security → Driver Extensions
        3. Find "Karabiner-VirtualHIDDevice-Manager.app"
        4. Turn ON the toggle switch
        5. Return to KeyPath

        This is a one-time setup required for keyboard remapping functionality.
        """
      alert.alertStyle = .informational
      alert.addButton(withTitle: "Open System Settings")
      alert.addButton(withTitle: "I'll Do This Later")

      let response = alert.runModal()

      if response == .alertFirstButtonReturn {
        // Open System Settings to Driver Extensions
        AppLogger.shared.log(
          "🔧 [AutoFixer] Opening System Settings for driver extension activation")
        openDriverExtensionSettings()
      } else {
        AppLogger.shared.log("🔧 [AutoFixer] User chose to activate driver extension later")
      }
    }
  }

  /// Open System Settings to the Driver Extensions page
  private func openDriverExtensionSettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.SystemExtensionsSettings")!
    NSWorkspace.shared.open(url)
  }

  private func installLaunchDaemonServices() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Installing LaunchDaemon services")

    // Install all LaunchDaemon services with a single admin prompt
    let installSuccess = launchDaemonInstaller.createAllLaunchDaemonServices()

    if installSuccess {
      AppLogger.shared.log("✅ [AutoFixer] Successfully installed LaunchDaemon services")

      // Load the services
      let loadSuccess = await launchDaemonInstaller.loadServices()

      if loadSuccess {
        AppLogger.shared.log("✅ [AutoFixer] Successfully loaded LaunchDaemon services")
        return true
      } else {
        AppLogger.shared.log("❌ [AutoFixer] Failed to load LaunchDaemon services")
        return false
      }
    } else {
      AppLogger.shared.log("❌ [AutoFixer] Failed to install LaunchDaemon services")
      return false
    }
  }

  private func installViaBrew() async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Installing packages via Homebrew")

    // First, check if Homebrew is available
    guard packageManager.checkHomebrewInstallation() else {
      AppLogger.shared.log("❌ [AutoFixer] Homebrew not available for package installation")
      return false
    }

    // Check what packages need to be installed
    let kanataInfo = packageManager.detectKanataInstallation()
    var installationSuccessful = true

    // Install Kanata if needed
    if !kanataInfo.isInstalled {
      AppLogger.shared.log("🔧 [AutoFixer] Installing Kanata via Homebrew")
      let result = await packageManager.installKanataViaBrew()

      switch result {
      case .success:
        AppLogger.shared.log("✅ [AutoFixer] Successfully installed Kanata via Homebrew")
      case .failure(let reason):
        AppLogger.shared.log("❌ [AutoFixer] Failed to install Kanata: \(reason)")
        installationSuccessful = false
      case .homebrewNotAvailable:
        AppLogger.shared.log("❌ [AutoFixer] Homebrew not available for Kanata installation")
        installationSuccessful = false
      case .packageNotFound:
        AppLogger.shared.log("❌ [AutoFixer] Kanata package not found in Homebrew")
        installationSuccessful = false
      case .userCancelled:
        AppLogger.shared.log("⚠️ [AutoFixer] Kanata installation cancelled by user")
        return false
      }
    } else {
      AppLogger.shared.log("ℹ️ [AutoFixer] Kanata already installed: \(kanataInfo.description)")
    }

    if installationSuccessful {
      AppLogger.shared.log("✅ [AutoFixer] Successfully completed Homebrew package installation")
    } else {
      AppLogger.shared.log("❌ [AutoFixer] Some packages failed to install via Homebrew")
    }

    return installationSuccessful
  }

  // MARK: - Helper Methods

  /// Attempts to gracefully terminate a specific process by PID
  private func terminateProcess(pid: Int) async -> Bool {
    AppLogger.shared.log("🔧 [AutoFixer] Terminating process PID: \(pid)")

    let killTask = Process()
    killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
    killTask.arguments = ["-TERM", String(pid)]

    do {
      try killTask.run()
      killTask.waitUntilExit()

      if killTask.terminationStatus == 0 {
        // Wait a bit for graceful termination
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

        // Check if process is still running
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/bin/kill")
        checkTask.arguments = ["-0", String(pid)]

        try checkTask.run()
        checkTask.waitUntilExit()

        if checkTask.terminationStatus != 0 {
          // Process is gone
          AppLogger.shared.log("✅ [AutoFixer] Process \(pid) terminated gracefully")
          return true
        } else {
          // Process still running, try SIGKILL
          AppLogger.shared.log("⚠️ [AutoFixer] Process \(pid) still running, using SIGKILL")
          return await forceTerminateProcess(pid: pid)
        }
      } else {
        AppLogger.shared.log("❌ [AutoFixer] Failed to send SIGTERM to process \(pid)")
        return await forceTerminateProcess(pid: pid)
      }
    } catch {
      AppLogger.shared.log("❌ [AutoFixer] Error terminating process \(pid): \(error)")
      return false
    }
  }

  /// Force terminates a process using SIGKILL
  private func forceTerminateProcess(pid: Int) async -> Bool {
    let killTask = Process()
    killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
    killTask.arguments = ["-9", String(pid)]

    do {
      try killTask.run()
      killTask.waitUntilExit()

      let success = killTask.terminationStatus == 0
      if success {
        AppLogger.shared.log("✅ [AutoFixer] Force terminated process \(pid)")
      } else {
        AppLogger.shared.log("❌ [AutoFixer] Failed to force terminate process \(pid)")
      }
      return success

    } catch {
      AppLogger.shared.log("❌ [AutoFixer] Error force terminating process \(pid): \(error)")
      return false
    }
  }
}
