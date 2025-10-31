import AppKit
import Foundation

// MARK: - Protocol

/// Service for detecting and resolving conflicts with Karabiner-Elements
@MainActor
protocol KarabinerConflictManaging: AnyObject {
    // Detection
    func isKarabinerDriverInstalled() -> Bool
    func isKarabinerDriverExtensionEnabled() -> Bool
    func areKarabinerBackgroundServicesEnabled() -> Bool
    func isKarabinerElementsRunning() -> Bool
    func isKarabinerDaemonRunning() -> Bool

    // Resolution
    func killKarabinerGrabber() async -> Bool
    func disableKarabinerElementsPermanently() async -> Bool
    func startKarabinerDaemon() async -> Bool

    // Utilities
    func getKillKarabinerCommand() -> String
}

// MARK: - Implementation

/// Manages detection and resolution of conflicts with Karabiner-Elements
@MainActor
final class KarabinerConflictService: KarabinerConflictManaging {
    // MARK: - Constants

    private let driverPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    private let daemonPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    private let disabledMarkerPath = "\(NSHomeDirectory())/.keypath/karabiner-grabber-disabled"

    // MARK: - Detection Methods

    func isKarabinerDriverInstalled() -> Bool {
        FileManager.default.fileExists(atPath: driverPath)
    }

    func isKarabinerDriverExtensionEnabled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        task.arguments = ["list"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Look for Karabiner driver with [activated enabled] status
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"),
                   line.contains("[activated enabled]") {
                    AppLogger.shared.log("✅ [Driver] Karabiner driver extension is enabled")
                    return true
                }
            }

            AppLogger.shared.log("⚠️ [Driver] Karabiner driver extension not enabled or not found")
            AppLogger.shared.log("⚠️ [Driver] systemextensionsctl output:\n\(output)")
            return false
        } catch {
            AppLogger.shared.log("❌ [Driver] Error checking driver extension status: \(error)")
            return false
        }
    }

    func areKarabinerBackgroundServicesEnabled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Check for Karabiner services in the user's launchctl list
            let hasServices = output.contains("org.pqrs.service.agent.karabiner")

            if hasServices {
                AppLogger.shared.log("✅ [Services] Karabiner background services detected")
            } else {
                AppLogger.shared.log(
                    "⚠️ [Services] Karabiner background services not found - may not be enabled in Login Items"
                )
            }

            return hasServices
        } catch {
            AppLogger.shared.log("❌ [Services] Error checking background services: \(error)")
            return false
        }
    }

    func isKarabinerElementsRunning() -> Bool {
        // First check if we've permanently disabled the grabber
        if FileManager.default.fileExists(atPath: disabledMarkerPath) {
            AppLogger.shared.log(
                "ℹ️ [Conflict] karabiner_grabber permanently disabled by KeyPath - skipping conflict check"
            )
            return false
        }

        // Check if Karabiner-Elements grabber is running (conflicts with Kanata)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "karabiner_grabber"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let isRunning = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if isRunning {
                AppLogger.shared.log(
                    "⚠️ [Conflict] karabiner_grabber is running - will conflict with Kanata"
                )
                AppLogger.shared.log(
                    "⚠️ [Conflict] This causes 'exclusive access' errors when starting Kanata"
                )
            } else {
                AppLogger.shared.log("✅ [Conflict] No karabiner_grabber detected")
            }

            return isRunning
        } catch {
            AppLogger.shared.log("❌ [Conflict] Error checking karabiner_grabber: \(error)")
            return false
        }
    }

    func isKarabinerDaemonRunning() -> Bool {
        // Skip daemon check during startup to prevent blocking
        if ProcessInfo.processInfo.environment["KEYPATH_STARTUP_MODE"] == "1" {
            AppLogger.shared.log(
                "🔍 [Daemon] Startup mode - skipping VirtualHIDDevice-Daemon check to prevent UI freeze"
            )
            return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "VirtualHIDDevice-Daemon"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            try task.run()

            // Use DispatchGroup to implement timeout
            let group = DispatchGroup()
            group.enter()

            DispatchQueue.global().async {
                task.waitUntilExit()
                group.leave()
            }

            let timeoutResult = group.wait(timeout: .now() + 2.0)
            if timeoutResult == .timedOut {
                task.terminate()
                AppLogger.shared.log(
                    "⚠️ [Daemon] VirtualHIDDevice-Daemon check timed out after 2s - assuming not running"
                )
                return false
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let isRunning = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            AppLogger.shared.log(
                "🔍 [Daemon] Karabiner VirtualHIDDevice-Daemon running: \(isRunning) (took \(String(format: "%.3f", duration))s)"
            )
            return isRunning
        } catch {
            AppLogger.shared.log("❌ [Daemon] Error checking VirtualHIDDevice-Daemon: \(error)")
            return false
        }
    }

    // MARK: - Resolution Methods

    func killKarabinerGrabber() async -> Bool {
        AppLogger.shared.log("🔧 [Conflict] Attempting to stop Karabiner conflicting services")

        let stopScript = """
        # Stop old Karabiner Elements system LaunchDaemon (runs as root)
        launchctl bootout system \\
            "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Privileged Daemons.app/Contents/Library/LaunchDaemons/org.pqrs.service.daemon.karabiner_grabber.plist" \\
            2>/dev/null || true

        # Stop old Karabiner Elements user LaunchAgent
        launchctl bootout gui/$(id -u) \\
            "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Non-Privileged Agents.app/Contents/Library/LaunchAgents/org.pqrs.service.agent.karabiner_grabber.plist" \\
            2>/dev/null || true

        # Kill old karabiner_grabber processes
        pkill -f karabiner_grabber 2>/dev/null || true

        # Kill VirtualHIDDevice processes that conflict with Kanata
        pkill -f "Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
        pkill -f "Karabiner-DriverKit-VirtualHIDDevice" 2>/dev/null || true

        # Wait for processes to terminate
        sleep 2

        # Final cleanup - force kill any stubborn processes
        pkill -9 -f karabiner_grabber 2>/dev/null || true
        pkill -9 -f "Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
        pkill -9 -f "Karabiner-DriverKit-VirtualHIDDevice" 2>/dev/null || true
        """

        let stopTask = Process()
        stopTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        stopTask.arguments = [
            "-e",
            "do shell script \"\(stopScript)\" with administrator privileges with prompt \"KeyPath needs to stop conflicting keyboard services.\""
        ]

        do {
            try stopTask.run()
            stopTask.waitUntilExit()
            AppLogger.shared.log("🔧 [Conflict] Attempted to stop all Karabiner grabber services")

            // Wait a moment for cleanup
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

            // Verify no conflicting processes are still running
            let success = await verifyConflictingProcessesStopped()

            if success {
                AppLogger.shared.log(
                    "✅ [Conflict] All conflicting Karabiner processes successfully stopped"
                )
            } else {
                AppLogger.shared.log("⚠️ [Conflict] Some conflicting processes may still be running")
            }

            return success

        } catch {
            AppLogger.shared.log("❌ [Conflict] Failed to stop Karabiner grabber: \(error)")
            return false
        }
    }

    func disableKarabinerElementsPermanently() async -> Bool {
        AppLogger.shared.log("🔧 [Karabiner] Starting permanent disable of Karabiner Elements services")

        // Ask user for permission first
        let userConsented = await requestPermissionToDisableKarabiner()
        guard userConsented else {
            AppLogger.shared.log("❌ [Karabiner] User declined permission to disable Karabiner Elements")
            return false
        }

        // Get the disable script
        let script = getDisableKarabinerElementsScript()

        // Execute with elevated privileges
        return await executeScriptWithSudo(
            script: script,
            description: "Disable Karabiner Elements Services"
        )
    }

    /// Restarts the Karabiner daemon with verified kill + start + health check
    /// Routes through PrivilegedOperationsCoordinator for unified privilege handling (helper-first, sudo fallback)
    func restartKarabinerDaemon() async -> Bool {
        AppLogger.shared.log("🔄 [Daemon] Restarting VirtualHIDDevice daemon (via coordinator)")

        do {
            let success = try await PrivilegedOperationsCoordinator.shared.restartKarabinerDaemonVerified()
            if success {
                AppLogger.shared.log("✅ [Daemon] Restart verified via coordinator")
            } else {
                AppLogger.shared.log("❌ [Daemon] Restart verification failed via coordinator")
            }
            return success
        } catch {
            AppLogger.shared.log("❌ [Daemon] Coordinator restart failed: \(error)")
            return false
        }
    }

    func startKarabinerDaemon() async -> Bool {
        guard FileManager.default.fileExists(atPath: daemonPath) else {
            AppLogger.shared.log("❌ [Daemon] VirtualHIDDevice-Daemon not found at \(daemonPath)")
            return false
        }

        // First try to start without admin privileges
        AppLogger.shared.log("🔄 [Daemon] Attempting to start daemon without admin privileges...")
        let userTask = Process()
        userTask.executableURL = URL(fileURLWithPath: daemonPath)

        let userPipe = Pipe()
        userTask.standardOutput = userPipe
        userTask.standardError = userPipe

        do {
            try userTask.run()
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            if isKarabinerDaemonRunning() {
                AppLogger.shared.log("✅ [Daemon] Successfully started daemon without admin privileges")
                return true
            } else {
                userTask.terminate()
                let userData = userPipe.fileHandleForReading.readDataToEndOfFile()
                let userOutput = String(data: userData, encoding: .utf8) ?? ""
                AppLogger.shared.log(
                    "⚠️ [Daemon] User-mode start failed, trying with admin privileges. Error: \(userOutput)"
                )
            }
        } catch {
            AppLogger.shared.log(
                "⚠️ [Daemon] User-mode start failed: \(error), trying with admin privileges"
            )
        }

        // Fallback: Use admin privileges via AppleScript
        AppLogger.shared.log("🔄 [Daemon] Starting daemon with admin privileges...")
        let adminScript =
            "do shell script \"\(daemonPath) > /dev/null 2>&1 &\" with administrator privileges with prompt \"KeyPath needs to start the virtual keyboard daemon.\""

        let adminTask = Process()
        adminTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        adminTask.arguments = ["-e", adminScript]

        let adminPipe = Pipe()
        adminTask.standardOutput = adminPipe
        adminTask.standardError = adminPipe

        do {
            try adminTask.run()
            adminTask.waitUntilExit()

            if adminTask.terminationStatus == 0 {
                AppLogger.shared.log("✅ [Daemon] Started daemon with admin privileges")
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                return isKarabinerDaemonRunning()
            } else {
                let adminData = adminPipe.fileHandleForReading.readDataToEndOfFile()
                let adminOutput = String(data: adminData, encoding: .utf8) ?? ""
                AppLogger.shared.log("❌ [Daemon] Failed to start with admin privileges: \(adminOutput)")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [Daemon] Failed to start VirtualHIDDevice-Daemon: \(error)")
            return false
        }
    }

    // MARK: - Utility Methods

    func getKillKarabinerCommand() -> String {
        """
        sudo launchctl unload /Library/LaunchDaemons/org.pqrs.karabiner.karabiner_grabber.plist
        sudo pkill -f karabiner_grabber
        """
    }

    // MARK: - Private Helper Methods

    private func requestPermissionToDisableKarabiner() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                if TestEnvironment.isRunningTests {
                    AppLogger.shared.log("🧪 [Karabiner] Auto-consenting in test environment (no NSAlert)")
                    continuation.resume(returning: true)
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Disable Karabiner Elements?"
                    alert.informativeText = """
                    Karabiner Elements is conflicting with Kanata.

                    Disable the conflicting services to allow KeyPath to work?

                    Note: Event Viewer and other Karabiner apps will continue working.
                    """
                    alert.addButton(withTitle: "Disable Conflicting Services")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .warning

                    let response = alert.runModal()
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            }
        }
    }

    private func getDisableKarabinerElementsScript() -> String {
        """
        #!/bin/bash

        echo "🔧 Permanently disabling conflicting Karabiner Elements services..."
        echo "ℹ️  Keeping Event Viewer and menu apps working"

        # Kill conflicting processes
        echo "Stopping conflicting processes..."
        pkill -f "karabiner_grabber" 2>/dev/null || true
        pkill -f "VirtualHIDDevice" 2>/dev/null || true
        echo "  ✓ Stopped karabiner_grabber and VirtualHIDDevice processes"

        echo "ℹ️  Keeping other Karabiner services running (they don't conflict)"

        # Disable karabiner_grabber services
        launchctl disable gui/$(id -u)/org.pqrs.service.agent.karabiner_grabber 2>/dev/null || true
        launchctl bootout gui/$(id -u) org.pqrs.service.agent.karabiner_grabber 2>/dev/null || true
        launchctl disable system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true
        launchctl bootout system org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true

        # Create marker file
        mkdir -p ~/.keypath
        touch ~/.keypath/karabiner-grabber-disabled

        echo "✅ Successfully disabled conflicting Karabiner services"
        """
    }

    private func executeScriptWithSudo(script: String, description: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let tempDir = NSTemporaryDirectory()
                let scriptPath = "\(tempDir)disable_karabiner_\(UUID().uuidString).sh"

                do {
                    // Write script to temporary file
                    try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

                    // Make script executable
                    let chmodTask = Process()
                    chmodTask.executableURL = URL(fileURLWithPath: "/bin/chmod")
                    chmodTask.arguments = ["+x", scriptPath]
                    try chmodTask.run()
                    chmodTask.waitUntilExit()

                    // Execute script with sudo using osascript
                    let osascriptCommand = """
                    do shell script "\(scriptPath)" with administrator privileges with prompt "KeyPath needs to \(description.lowercased()) to fix keyboard conflicts."
                    """

                    let osascriptTask = Process()
                    osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    osascriptTask.arguments = ["-e", osascriptCommand]

                    let pipe = Pipe()
                    osascriptTask.standardOutput = pipe
                    osascriptTask.standardError = pipe

                    try osascriptTask.run()
                    osascriptTask.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    // Clean up temporary file
                    try? FileManager.default.removeItem(atPath: scriptPath)

                    if osascriptTask.terminationStatus == 0 {
                        AppLogger.shared.log("✅ [Karabiner] Successfully disabled Karabiner Elements services")
                        AppLogger.shared.log("📝 [Karabiner] Output: \(output)")

                        // Perform additional verification
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            await self.verifyKarabinerGrabberRemoval()
                        }

                        continuation.resume(returning: true)
                    } else {
                        AppLogger.shared.log("❌ [Karabiner] Failed to disable Karabiner Elements services")
                        AppLogger.shared.log("📝 [Karabiner] Error output: \(output)")
                        continuation.resume(returning: false)
                    }

                } catch {
                    AppLogger.shared.log("❌ [Karabiner] Error executing disable script: \(error)")
                    try? FileManager.default.removeItem(atPath: scriptPath)
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func verifyKarabinerGrabberRemoval() async {
        AppLogger.shared.log("🔍 [Karabiner] Performing post-disable verification...")

        // Check if process is still running
        let isStillRunning = isKarabinerElementsRunning()
        if isStillRunning {
            AppLogger.shared.log(
                "⚠️ [Karabiner] WARNING: karabiner_grabber still detected after disable attempt"
            )
        } else {
            AppLogger.shared.log("✅ [Karabiner] VERIFIED: karabiner_grabber successfully removed")
        }

        // Check if service is still in launchctl list
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if output.contains("org.pqrs.service.agent.karabiner_grabber") {
                AppLogger.shared.log(
                    "⚠️ [Karabiner] WARNING: karabiner_grabber service still in launchctl list"
                )
            } else {
                AppLogger.shared.log(
                    "✅ [Karabiner] VERIFIED: karabiner_grabber service successfully unloaded"
                )
            }
        } catch {
            AppLogger.shared.log("❌ [Karabiner] Error checking launchctl status: \(error)")
        }
    }

    private func verifyConflictingProcessesStopped() async -> Bool {
        AppLogger.shared.log("🔍 [Conflict] Verifying conflicting processes have been stopped")

        let grabberCheck = await checkProcessStopped(
            pattern: "karabiner_grabber",
            processName: "karabiner_grabber"
        )

        let vhidDaemonCheck = await checkProcessStopped(
            pattern: "Karabiner-VirtualHIDDevice-Daemon",
            processName: "VirtualHIDDevice Daemon"
        )

        let vhidDriverCheck = await checkProcessStopped(
            pattern: "Karabiner-DriverKit-VirtualHIDDevice",
            processName: "VirtualHIDDevice Driver"
        )

        let allStopped = grabberCheck && vhidDaemonCheck && vhidDriverCheck

        if allStopped {
            AppLogger.shared.log("✅ [Conflict] Verification complete: No conflicting processes running")
        } else {
            AppLogger.shared.log("⚠️ [Conflict] Verification failed: Some processes still running")
        }

        return allStopped
    }

    private func checkProcessStopped(pattern: String, processName: String) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", pattern]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let isStopped = task.terminationStatus != 0 // pgrep returns 1 if no processes found

            if isStopped {
                AppLogger.shared.log("✅ [Conflict] \(processName) successfully stopped")
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                AppLogger.shared.log(
                    "⚠️ [Conflict] \(processName) still running: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }

            return isStopped
        } catch {
            AppLogger.shared.log("❌ [Conflict] Error checking \(processName): \(error)")
            return false
        }
    }
}
