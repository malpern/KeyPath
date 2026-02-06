import AppKit
import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore

/// Checks system requirements and installation status for KeyPath.
///
/// Extracted from RuntimeCoordinator to reduce its size and improve
/// separation of concerns. This service handles:
/// - Installation status detection
/// - Permission checking (via PermissionOracle)
/// - System requirements aggregation
/// - Opening System Settings for permissions
/// - Finder utilities for permission setup
@MainActor
final class SystemRequirementsChecker {
    // MARK: - Dependencies

    private let karabinerConflictService: KarabinerConflictManaging

    init(karabinerConflictService: KarabinerConflictManaging) {
        self.karabinerConflictService = karabinerConflictService
    }

    // MARK: - Installation Status

    /// Check if KeyPath is installed (binary exists)
    func isInstalled() -> Bool {
        // Use KanataBinaryDetector for consistent detection across wizard and UI
        // Canonical path architecture: system-installed kanata is the stable identity for permissions.
        KanataBinaryDetector.shared.isInstalled()
    }

    /// Check if KeyPath is completely installed (binary + service)
    func isCompletelyInstalled(isServiceInstalled: () -> Bool) -> Bool {
        isInstalled() && isServiceInstalled()
    }

    /// Get installation status string for UI display
    func getInstallationStatus(isServiceInstalled _: () -> Bool) -> String {
        let detector = KanataBinaryDetector.shared
        let detection = detector.detectCurrentStatus()
        let driverInstalled = isKarabinerDriverInstalled()

        switch detection.status {
        case .systemInstalled:
            return driverInstalled ? "✅ Fully installed" : "⚠️ Driver missing"
        case .bundledAvailable:
            return "⚠️ Kanata engine needs installation"
        case .bundledUnsigned:
            return "⚠️ Bundled Kanata unsigned (needs Developer ID signature)"
        case .missing:
            return "❌ Not installed"
        case .bundledMissing:
            return "⚠️ CRITICAL: App bundle corrupted - reinstall KeyPath"
        }
    }

    // MARK: - Permission Checking

    /// Check if KeyPath has Input Monitoring permission
    func hasInputMonitoringPermission() async -> Bool {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        return snapshot.keyPath.inputMonitoring.isReady
    }

    /// Check if KeyPath has Accessibility permission
    func hasAccessibilityPermission() async -> Bool {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        return snapshot.keyPath.accessibility.isReady
    }

    /// Check if KeyPath has all required permissions
    func hasAllRequiredPermissions() async -> Bool {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        return snapshot.keyPath.hasAllPermissions
    }

    /// Check permissions for both KeyPath and Kanata with detailed information
    func checkBothAppsHavePermissions() async -> (
        keyPathHasPermission: Bool, kanataHasPermission: Bool, permissionDetails: String
    ) {
        let snapshot = await PermissionOracle.shared.currentSnapshot()

        let keyPathPath = Bundle.main.bundlePath
        let kanataPath = WizardSystemPaths.kanataSystemInstallPath

        let keyPathHasInputMonitoring = snapshot.keyPath.inputMonitoring.isReady
        let keyPathHasAccessibility = snapshot.keyPath.accessibility.isReady
        let kanataHasInputMonitoring = snapshot.kanata.inputMonitoring.isReady
        let kanataHasAccessibility = snapshot.kanata.accessibility.isReady

        let keyPathOverall = keyPathHasInputMonitoring && keyPathHasAccessibility
        let kanataOverall = kanataHasInputMonitoring && kanataHasAccessibility

        let details = """
        KeyPath.app (\(keyPathPath)):
        - Input Monitoring: \(keyPathHasInputMonitoring ? "✅" : "❌")
        - Accessibility: \(keyPathHasAccessibility ? "✅" : "❌")

        kanata (\(kanataPath)):
        - Input Monitoring: \(kanataHasInputMonitoring ? "✅" : "❌")
        - Accessibility: \(kanataHasAccessibility ? "✅" : "❌")
        """

        return (keyPathOverall, kanataOverall, details)
    }

    // MARK: - System Requirements

    /// Check if all system requirements are met
    func hasAllSystemRequirements(isServiceInstalled _: () -> Bool) async -> Bool {
        let hasPermissions = await hasAllRequiredPermissions()
        let daemonRunning = await isKarabinerDaemonRunning()
        return isInstalled() && hasPermissions && isKarabinerDriverInstalled() && daemonRunning
    }

    /// Get detailed system requirements status
    func getSystemRequirementsStatus(isServiceInstalled _: () -> Bool) async -> (
        installed: Bool, permissions: Bool, driver: Bool, daemon: Bool
    ) {
        let permissions = await hasAllRequiredPermissions()
        return await (
            installed: isInstalled(),
            permissions: permissions,
            driver: isKarabinerDriverInstalled(),
            daemon: isKarabinerDaemonRunning()
        )
    }

    // MARK: - System Settings

    /// Open Input Monitoring settings in System Settings
    func openInputMonitoringSettings() {
        if let url = URL(string: KeyPathConstants.URLs.inputMonitoringPrivacy) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open Accessibility settings in System Settings
    func openAccessibilitySettings() {
        if #available(macOS 13.0, *) {
            if let url = URL(string: KeyPathConstants.URLs.accessibilityPrivacy) {
                NSWorkspace.shared.open(url)
            }
        } else {
            if let url = URL(string: KeyPathConstants.URLs.accessibilityPrivacy) {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: KeyPathConstants.System.securityPrefPane)
                )
            }
        }
    }

    // MARK: - Finder Utilities

    /// Reveal the canonical kanata binary in Finder to assist drag-and-drop into permissions
    func revealKanataInFinder(onRevealed: (() -> Void)? = nil) {
        let kanataPath = WizardSystemPaths.kanataSystemInstallPath
        let folderPath = (kanataPath as NSString).deletingLastPathComponent

        let script = """
        tell application "Finder"
            activate
            set targetFolder to POSIX file "\(folderPath)" as alias
            set targetWindow to make new Finder window to targetFolder
            set current view of targetWindow to icon view
            set arrangement of icon view options of targetWindow to arranged by name
            set bounds of targetWindow to {200, 140, 900, 800}
            select POSIX file "\(kanataPath)" as alias
            delay 0.5
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error {
                AppLogger.shared.error("❌ [Finder] AppleScript error revealing kanata: \(error)")
            } else {
                AppLogger.shared.info("✅ [Finder] Revealed kanata in Finder: \(kanataPath)")
                // Call callback after delay to allow Finder to open
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onRevealed?()
                }
            }
        } else {
            AppLogger.shared.error("❌ [Finder] Could not create AppleScript to reveal kanata.")
        }
    }

    // MARK: - Karabiner Status (delegates to KarabinerConflictService)

    func isKarabinerDriverInstalled() -> Bool {
        karabinerConflictService.isKarabinerDriverInstalled()
    }

    func isKarabinerDriverExtensionEnabled() async -> Bool {
        await karabinerConflictService.isKarabinerDriverExtensionEnabled()
    }

    func areKarabinerBackgroundServicesEnabled() async -> Bool {
        await karabinerConflictService.areKarabinerBackgroundServicesEnabled()
    }

    func isKarabinerElementsRunning() async -> Bool {
        await karabinerConflictService.isKarabinerElementsRunning()
    }

    func disableKarabinerElementsPermanently() async -> Bool {
        await karabinerConflictService.disableKarabinerElementsPermanently()
    }

    func killKarabinerGrabber() async -> Bool {
        await karabinerConflictService.killKarabinerGrabber()
    }

    func isKarabinerDaemonRunning() async -> Bool {
        await karabinerConflictService.isKarabinerDaemonRunning()
    }

    func startKarabinerDaemon() async -> Bool {
        await karabinerConflictService.startKarabinerDaemon()
    }

    func restartKarabinerDaemon() async -> Bool {
        await karabinerConflictService.restartKarabinerDaemon()
    }

    // MARK: - VirtualHID Diagnostics

    /// Diagnostic summary explaining why VirtualHID service is considered broken
    /// Used to surface a helpful error toast in the wizard
    func getVirtualHIDBreakageSummary(diagnosticsService: DiagnosticsServiceProtocol) async -> String {
        // Gather low-level daemon state via DiagnosticsService
        let status = await diagnosticsService.virtualHIDDaemonStatus()

        // Driver extension + version
        let driverEnabled = await isKarabinerDriverExtensionEnabled()
        let vhid = VHIDDeviceManager()
        let installedVersion = vhid.getInstalledVersion() ?? "unknown"
        let hasMismatch = vhid.hasVersionMismatch()
        let securityIssues = await vhid.securityPreflightIssues()

        return Self.makeVirtualHIDBreakageSummary(
            status: status,
            driverEnabled: driverEnabled,
            installedVersion: installedVersion,
            hasMismatch: hasMismatch,
            securityIssues: securityIssues
        )
    }

    /// Create VirtualHID breakage summary (extracted for testability)
    static func makeVirtualHIDBreakageSummary(
        status: VirtualHIDDaemonStatus,
        driverEnabled: Bool,
        installedVersion: String,
        hasMismatch: Bool,
        securityIssues: [String] = []
    ) -> String {
        var lines: [String] = []
        if status.pids.count > 1 {
            lines.append("Reason: Multiple VirtualHID daemons detected (\(status.pids.count)).")
            lines.append("PIDs: \(status.pids.joined(separator: ", "))")
            if !status.owners.isEmpty {
                lines.append("Owners:\n\(status.owners.joined(separator: "\n"))")
            }
        } else if status.pids.isEmpty {
            lines.append("Reason: VirtualHID daemon not running.")
        } else {
            // Single PID present
            let serviceHealth = status.serviceHealthy
            if serviceHealth == false {
                lines.append(
                    "Reason: Daemon running (PID \(status.pids[0])) but launchctl health check failed."
                )
                lines.append(
                    "This often indicates a stale service registration, but the driver may still work."
                )
            } else {
                lines.append("Daemon running (PID \(status.pids[0])) and launchctl reports healthy.")
                lines.append("If the wizard still shows red, click Fix to resync status.")
            }
            lines.append("PID: \(status.pids[0])")
            if !status.owners.isEmpty { lines.append("Owner:\n\(status.owners.joined(separator: "\n"))") }
        }
        let launchState = status.serviceInstalled ? "installed" : "not installed"
        let launchSuffix = status.serviceInstalled ? ", \(status.serviceState)" : ""
        lines.append("LaunchDaemon: \(launchState)\(launchSuffix)")
        lines.append("Driver extension: \(driverEnabled ? "enabled" : "disabled")")
        let versionSuffix = hasMismatch ? " (incompatible with current Kanata)" : ""
        lines.append("Driver version: \(installedVersion)\(versionSuffix)")
        if !securityIssues.isEmpty {
            lines.append("Security checks:")
            lines.append(contentsOf: securityIssues.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}
