import AppKit
import Foundation
import KeyPathCore

// MARK: - Protocol

/// Service for detecting and resolving conflicts with Karabiner-Elements
@MainActor
protocol KarabinerConflictManaging: AnyObject {
    // Detection
    func isKarabinerDriverInstalled() -> Bool
    func isKarabinerDriverExtensionEnabled() async -> Bool
    func areKarabinerBackgroundServicesEnabled() async -> Bool
    func isKarabinerElementsRunning() async -> Bool
    func isKarabinerDaemonRunning() async -> Bool

    // Resolution
    func killKarabinerGrabber() async -> Bool
    func disableKarabinerElementsPermanently() async -> Bool
    func startKarabinerDaemon() async -> Bool
    func restartKarabinerDaemon() async -> Bool
}

// MARK: - Implementation

/// Manages detection and resolution of conflicts with Karabiner-Elements
@MainActor
final class KarabinerConflictService: KarabinerConflictManaging {
    // MARK: - Dependencies

    private let engineFactory: () -> (any InstallerEnginePrivilegedRouting)
    private let brokerFactory: () -> PrivilegeBroker

    init(
        engineFactory: @escaping () -> (any InstallerEnginePrivilegedRouting) = { InstallerEngine() },
        brokerFactory: @escaping () -> PrivilegeBroker = { PrivilegeBroker() }
    ) {
        self.engineFactory = engineFactory
        self.brokerFactory = brokerFactory
    }

    // MARK: - Constants

    private let driverPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    private let daemonPath =
        "/Library/Application Support/org.pqrs/" + "Karabiner-DriverKit-VirtualHIDDevice/Applications/"
            + "Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/" + "Karabiner-VirtualHIDDevice-Daemon"
    private let disabledMarkerPath = "\(NSHomeDirectory())/.keypath/karabiner-grabber-disabled"
    private let vhidDaemonLabel = "com.keypath.karabiner-vhiddaemon"
    private let vhidDaemonPlist = "/Library/LaunchDaemons/com.keypath.karabiner-vhiddaemon.plist"

    // MARK: - Detection Methods

    func isKarabinerDriverInstalled() -> Bool {
        FileManager.default.fileExists(atPath: driverPath)
    }

    func isKarabinerDriverExtensionEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            Task {
                do {
                    let result = try await SubprocessRunner.shared.run(
                        "/usr/bin/systemextensionsctl",
                        args: ["list"],
                        timeout: 5
                    )

                    let output = result.stdout

                    // Look for Karabiner driver with [activated enabled] status
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"),
                           line.contains("[activated enabled]") {
                            AppLogger.shared.log("✅ [Driver] Karabiner driver extension is enabled")
                            continuation.resume(returning: true)
                            return
                        }
                    }

                    AppLogger.shared.log("⚠️ [Driver] Karabiner driver extension not enabled or not found")
                    AppLogger.shared.log("⚠️ [Driver] systemextensionsctl output:\n\(output)")
                    continuation.resume(returning: false)
                } catch {
                    AppLogger.shared.log("❌ [Driver] Error checking driver extension status: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func areKarabinerBackgroundServicesEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            Task {
                do {
                    let result = try await SubprocessRunner.shared.launchctl("list", [])
                    let output = result.stdout

                    // Check for Karabiner services in the user's launchctl list
                    let hasServices = output.contains("org.pqrs.service.agent.karabiner")

                    if hasServices {
                        AppLogger.shared.log("✅ [Services] Karabiner background services detected")
                    } else {
                        AppLogger.shared.log(
                            "⚠️ [Services] Karabiner background services not found - may not be enabled in Login Items"
                        )
                    }

                    continuation.resume(returning: hasServices)
                } catch {
                    AppLogger.shared.log("❌ [Services] Error checking background services: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func isKarabinerElementsRunning() async -> Bool {
        // First check if we've permanently disabled the grabber
        if FileManager.default.fileExists(atPath: disabledMarkerPath) {
            AppLogger.shared.log(
                "ℹ️ [Conflict] karabiner_grabber permanently disabled by KeyPath - skipping conflict check"
            )
            return false
        }

        // Check if Karabiner-Elements grabber is running (conflicts with Kanata)
        return await withCheckedContinuation { continuation in
            Task {
                let pids = await SubprocessRunner.shared.pgrep("karabiner_grabber")
                let isRunning = !pids.isEmpty

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

                continuation.resume(returning: isRunning)
            }
        }
    }

    func isKarabinerDaemonRunning() async -> Bool {
        // Skip daemon check during startup to prevent blocking
        if FeatureFlags.shared.startupModeActive {
            AppLogger.shared.log(
                "🔍 [Daemon] Startup mode - skipping VirtualHIDDevice-Daemon check to prevent UI freeze (treat as healthy)"
            )
            return true
        }

        // Check if daemon was recently restarted - if so, consider it healthy during warm-up window
        // This aligns with ServiceHealthChecker.isServiceHealthy() warm-up logic
        if ServiceBootstrapper.wasRecentlyRestarted("com.keypath.karabiner-vhiddaemon") {
            AppLogger.shared.log(
                "🔍 [Daemon] VirtualHIDDevice-Daemon in warm-up window (recently restarted) - treating as healthy"
            )
            return true
        }

        return await withCheckedContinuation { continuation in
            Task {
                let startTime = CFAbsoluteTimeGetCurrent()
                let pids = await SubprocessRunner.shared.pgrep("VirtualHIDDevice-Daemon")
                let isRunning = !pids.isEmpty

                let duration = CFAbsoluteTimeGetCurrent() - startTime
                AppLogger.shared.log(
                    "🔍 [Daemon] Karabiner VirtualHIDDevice-Daemon running: \(isRunning) (took \(String(format: "%.3f", duration))s)"
                )
                continuation.resume(returning: isRunning)
            }
        }
    }

    // MARK: - Resolution Methods

    func killKarabinerGrabber() async -> Bool {
        AppLogger.shared.log("🔧 [Conflict] Stopping Karabiner conflicting services via InstallerEngine")
        do {
            let engine = engineFactory()
            let broker = brokerFactory()
            try await engine.disableKarabinerGrabber(using: broker)
            // Verify no conflicting processes remain
            try? await Task.sleep(for: .milliseconds(500))
            let success = await verifyConflictingProcessesStopped()
            if success {
                AppLogger.shared.log("✅ [Conflict] Karabiner grabber disabled and processes stopped")
            } else {
                AppLogger.shared.log("⚠️ [Conflict] Some conflicting processes may still be running")
            }
            return success
        } catch {
            AppLogger.shared.log("❌ [Conflict] Disable failed: \(error)")
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

        do {
            let engine = engineFactory()
            let broker = brokerFactory()
            try await engine.disableKarabinerGrabber(using: broker)
            await verifyKarabinerGrabberRemoval()
            return true
        } catch {
            AppLogger.shared.log("❌ [Karabiner] Disable failed: \(error)")
            return false
        }
    }

    /// Restarts the Karabiner daemon with verified kill + start + health check
    /// Routes through InstallerEngine per AGENTS.md
    func restartKarabinerDaemon() async -> Bool {
        AppLogger.shared.log("🔄 [Daemon] Restarting VirtualHIDDevice daemon (via InstallerEngine)")

        do {
            let engine = engineFactory()
            let broker = brokerFactory()
            let success = try await engine.restartKarabinerDaemon(using: broker)
            if success {
                AppLogger.shared.log("✅ [Daemon] Restart verified via InstallerEngine")
            } else {
                AppLogger.shared.log("❌ [Daemon] Restart verification failed via InstallerEngine")
            }
            return success
        } catch {
            AppLogger.shared.log("❌ [Daemon] Restart failed: \(error)")
            return false
        }
    }

    func startKarabinerDaemon() async -> Bool {
        // Route through InstallerEngine per AGENTS.md
        AppLogger.shared.log("🔄 [Daemon] Starting VHID daemon via InstallerEngine")
        do {
            let engine = engineFactory()
            let broker = brokerFactory()
            let ok = try await engine.restartKarabinerDaemon(using: broker)
            if ok {
                AppLogger.shared.log("✅ [Daemon] VHID daemon start verified via InstallerEngine")
            } else {
                AppLogger.shared.log("❌ [Daemon] VHID daemon start failed verification")
            }
            return ok
        } catch {
            AppLogger.shared.log("❌ [Daemon] Start failed: \(error)")
            return false
        }
    }

    // MARK: - Utility Methods

    // Removed legacy command string helper to avoid reintroducing unload/load usage

    // MARK: - Private Helper Methods

    private func requestPermissionToDisableKarabiner() async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
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
            Task.detached {
                let tempDir = NSTemporaryDirectory()
                let scriptPath = "\(tempDir)disable_karabiner_\(UUID().uuidString).sh"

                do {
                    // Write script to temporary file
                    try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

                    // Make script executable
                    _ = try await SubprocessRunner.shared.run(
                        "/bin/chmod",
                        args: ["+x", scriptPath],
                        timeout: 5
                    )

                    // Execute script with admin privileges (uses sudo if KEYPATH_USE_SUDO=1, otherwise osascript)
                    let result = PrivilegedCommandRunner.execute(
                        command: scriptPath,
                        prompt: "KeyPath needs to \(description.lowercased()) to fix keyboard conflicts."
                    )
                    let output = result.output

                    // Clean up temporary file
                    try? FileManager.default.removeItem(atPath: scriptPath)

                    if result.success {
                        AppLogger.shared.log("✅ [Karabiner] Successfully disabled Karabiner Elements services")
                        AppLogger.shared.log("📝 [Karabiner] Output: \(output)")

                        // Perform additional verification
                        Task {
                            try? await Task.sleep(for: .seconds(1))
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
        let isStillRunning = await isKarabinerElementsRunning()
        if isStillRunning {
            AppLogger.shared.log(
                "⚠️ [Karabiner] WARNING: karabiner_grabber still detected after disable attempt"
            )
        } else {
            AppLogger.shared.log("✅ [Karabiner] VERIFIED: karabiner_grabber successfully removed")
        }

        // Check if service is still in launchctl list
        do {
            let result = try await SubprocessRunner.shared.launchctl("list", [])
            let output = result.stdout

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
        let pids = await SubprocessRunner.shared.pgrep(pattern)
        let isStopped = pids.isEmpty // pgrep returns empty array if no processes found

        if isStopped {
            AppLogger.shared.log("✅ [Conflict] \(processName) successfully stopped")
        } else {
            AppLogger.shared.log(
                "⚠️ [Conflict] \(processName) still running: PIDs \(pids.map { String($0) }.joined(separator: ", "))"
            )
        }

        return isStopped
    }
}
