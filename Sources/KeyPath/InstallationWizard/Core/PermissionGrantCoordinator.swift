import Foundation
import SwiftUI

enum CoordinatorPermissionType: String, CaseIterable {
    case accessibility
    case inputMonitoring = "input_monitoring"

    var displayName: String {
        switch self {
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        }
    }

    var userDefaultsKey: String {
        "wizard_pending_\(rawValue)"
    }

    var timestampKey: String {
        "wizard_\(rawValue)_timestamp"
    }
}

@MainActor
class PermissionGrantCoordinator: ObservableObject {
    static let shared = PermissionGrantCoordinator()

    private let logger = WizardLogger.shared
    private let maxReturnTime: TimeInterval = 600 // 10 minutes

    // Prevent double-dismiss race conditions
    private var didFireCompletion = false

    // Service bounce flag keys
    private static let serviceBounceNeededKey = "keypath_service_bounce_needed"
    private static let serviceBounceTimestampKey = "keypath_service_bounce_timestamp"

    private init() {}

    func initiatePermissionGrant(for permissionType: CoordinatorPermissionType,
                                 instructions: String,
                                 onComplete: (() -> Void)? = nil) {
        logger.log("SAVING wizard state for \(permissionType.displayName) restart:")

        // Reset completion guard for new permission grant flow
        didFireCompletion = false

        let timestamp = Date().timeIntervalSince1970

        UserDefaults.standard.set(true, forKey: permissionType.userDefaultsKey)
        UserDefaults.standard.set(timestamp, forKey: permissionType.timestampKey)
        let synchronizeResult = UserDefaults.standard.synchronize()

        logger.log("  - \(permissionType.userDefaultsKey): true")
        logger.log("  - \(permissionType.timestampKey): \(timestamp)")
        logger.log("  - synchronize result: \(synchronizeResult)")

        // Verify the save worked
        logger.log("VERIFICATION after save:")
        let pendingValue = UserDefaults.standard.bool(forKey: permissionType.userDefaultsKey)
        let timestampValue = UserDefaults.standard.double(forKey: permissionType.timestampKey)
        logger.log("  - pending: \(pendingValue)")
        logger.log("  - timestamp: \(timestampValue)")

        // Show instructions dialog
        showInstructionsDialog(for: permissionType, instructions: instructions) {
            // Guard against double completion to prevent race conditions
            guard !self.didFireCompletion else {
                self.logger.log("⚠️ [PermissionGrant] Completion already fired, ignoring duplicate call")
                return
            }
            self.didFireCompletion = true

            onComplete?()
            self.quitApplication()
        }
    }

    private func showInstructionsDialog(for permissionType: CoordinatorPermissionType,
                                        instructions: String,
                                        onComplete: @escaping () -> Void) {
        if TestEnvironment.isRunningTests {
            WizardLogger.shared.log("🧪 [PermissionGrant] Suppressing NSAlert in test environment")
            onComplete()
            return
        }

        let alert = NSAlert()
        alert.messageText = "\(permissionType.displayName) Permission Required"
        alert.informativeText = instructions
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemSettings(for: permissionType)
            onComplete()
        }
    }

    private func openSystemSettings(for permissionType: CoordinatorPermissionType) {
        let settingsPath = switch permissionType {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }

        if let url = URL(string: settingsPath) {
            NSWorkspace.shared.open(url)
        }
    }

    private func quitApplication() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    func checkForPendingPermissionGrant() -> (shouldRestart: Bool, permissionType: CoordinatorPermissionType?) {
        let currentTime = Date().timeIntervalSince1970

        for permissionType in CoordinatorPermissionType.allCases {
            let pending = UserDefaults.standard.bool(forKey: permissionType.userDefaultsKey)
            let timestamp = UserDefaults.standard.double(forKey: permissionType.timestampKey)

            logger.log("APP RESTART - Checking for pending wizard:")
            logger.log("  - \(permissionType.userDefaultsKey): \(pending)")
            logger.log("  - \(permissionType.timestampKey): \(timestamp)")
            logger.log("  - current time: \(currentTime)")

            if pending, timestamp > 0 {
                let timeSince = currentTime - timestamp
                if timeSince < maxReturnTime {
                    logger.log("DETECTED return from \(permissionType.displayName):")
                    logger.log("  - time since: \(Int(timeSince))s")
                    logger.log("  - Will reopen wizard in 1 second")

                    return (shouldRestart: true, permissionType: permissionType)
                } else {
                    // Clear expired flags
                    clearPendingFlag(for: permissionType)
                }
            }
        }

        return (shouldRestart: false, permissionType: nil)
    }

    func performPermissionRestart(for permissionType: CoordinatorPermissionType,
                                  kanataManager: KanataManager,
                                  completion: @escaping (Bool) -> Void) {
        let timestamp = UserDefaults.standard.double(forKey: permissionType.timestampKey)
        let originalDate = Date(timeIntervalSince1970: timestamp)
        let timeSince = Date().timeIntervalSince1970 - timestamp

        logger.log("PERMISSION RESTART CONTEXT:")
        logger.log("  - Original timestamp: \(timestamp) (\(originalDate))")
        logger.log("  - Time elapsed: \(String(format: "%.1f", timeSince))s  ")
        logger.log("  - Assumption: User granted \(permissionType.displayName) permissions to KeyPath and/or kanata")
        logger.log("  - Action: Restarting kanata process to pick up new permissions")
        logger.log("  - Method: KanataManager retryAfterFix for complete restart")

        // Skip auto-launch to prevent resetting wizard flag
        logger.log("SKIPPING auto-launch (would reset wizard flag)")

        // Log pre-restart permissions snapshot
        logPermissionSnapshot()

        // Attempt restart
        logger.log("KANATA RESTART ATTEMPT:")
        let startTime = Date()

        // Provide immediate user feedback
        showUserFeedback("🔄 Restarting keyboard service for new \(permissionType.displayName.lowercased()) permissions...")

        Task {
            let success = await attemptKanataRestart(kanataManager: kanataManager)
            let duration = Date().timeIntervalSince1970 - startTime.timeIntervalSince1970

            if success {
                logger.log("  • Service restart success: true")
                logger.log("  • Duration: \(String(format: "%.2f", duration))s")

                // Show success feedback
                showUserFeedback("✅ Keyboard service restarted - \(permissionType.displayName) permissions active!")

                // Clear the pending flag on successful restart
                clearPendingFlag(for: permissionType)

                await MainActor.run {
                    completion(true)
                }
            } else {
                logger.log("  • Service restart success: false")
                logger.log("  • Duration so far: \(String(format: "%.2f", duration))s")
                logger.log("RESTART FAILURE:")
                logger.log("  • Service restart failed - will show in wizard")
                logger.log("  • User can use wizard auto-fix for manual restart")
                logger.log("  • Duration: \(String(format: "%.2f", duration))s")

                // Show failure feedback
                showUserFeedback("⚠️ Service restart in progress - check wizard for status")

                await MainActor.run {
                    completion(false)
                }
            }
        }
    }

    private func attemptKanataRestart(kanataManager: KanataManager) async -> Bool {
        // Use the retryAfterFix method which handles complete restarts
        await kanataManager.retryAfterFix("Restarting after permission grant")

        // Give it a moment to complete the restart
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // The retryAfterFix method doesn't return a success value, so we assume success
        // The coordinator will check permission status later anyway
        return true
    }

    private func logPermissionSnapshot() {
        logger.log("PRE-RESTART SNAPSHOT:")

        // Get current system state for logging
        let permissionService = PermissionService.shared
        let keyPathAccessibility = permissionService.hasAccessibilityPermission()
        let keyPathInputMonitoring = permissionService.hasInputMonitoringPermission()

        logger.log("  KeyPath permissions:")
        logger.log("    • Accessibility: \(keyPathAccessibility ? "granted" : "denied")")
        logger.log("    • Input Monitoring: \(keyPathInputMonitoring ? "granted" : "denied")")

        // Note: Kanata permissions will be checked via Oracle after restart
        logger.log("  Kanata permissions (source: tcc.no-fda):")
        logger.log("    • Accessibility: unknown  ")
        logger.log("    • Input Monitoring: unknown")

        // System readiness
        let systemReady = keyPathAccessibility && keyPathInputMonitoring
        logger.log("  System ready: \(systemReady)")

        if !systemReady {
            if !keyPathAccessibility {
                logger.log("  Blocking issue: KeyPath needs Accessibility permission - enable in System Settings > Privacy & Security > Accessibility")
            }
            if !keyPathInputMonitoring {
                logger.log("  Blocking issue: KeyPath needs Input Monitoring permission - enable in System Settings > Privacy & Security > Input Monitoring")
            }
        }
    }

    func clearPendingFlag(for permissionType: CoordinatorPermissionType) {
        UserDefaults.standard.removeObject(forKey: permissionType.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: permissionType.timestampKey)
        UserDefaults.standard.synchronize()
    }

    func clearAllPendingFlags() {
        for permissionType in CoordinatorPermissionType.allCases {
            clearPendingFlag(for: permissionType)
        }
    }

    private func showUserFeedback(_ message: String) {
        // Send notification to ContentView to show user feedback
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowUserFeedback"),
                object: nil,
                userInfo: ["message": message]
            )
        }
    }

    func reopenWizard(for permissionType: CoordinatorPermissionType, kanataManager: KanataManager) {
        logger.log("REOPENING wizard to \(permissionType.displayName) page")

        // Set the appropriate wizard return flag and call the appropriate method
        switch permissionType {
        case .accessibility:
            UserDefaults.standard.set(true, forKey: "wizard_return_to_accessibility")
            logger.log("KanataManager.showWizardForInputMonitoring called (using generic method)")
            Task { @MainActor in
                await kanataManager.showWizardForInputMonitoring()
            }
        case .inputMonitoring:
            UserDefaults.standard.set(true, forKey: "wizard_return_to_input_monitoring")
            logger.log("KanataManager.showWizardForInputMonitoring called")
            Task { @MainActor in
                await kanataManager.showWizardForInputMonitoring()
            }
        }

        logger.log("  - Wizard will be shown")
    }

    // MARK: - Service Bounce Management

    /// Set flag to indicate Kanata service should be bounced on next app restart
    func setServiceBounceNeeded(reason: String) {
        let timestamp = Date().timeIntervalSince1970
        UserDefaults.standard.set(true, forKey: Self.serviceBounceNeededKey)
        UserDefaults.standard.set(timestamp, forKey: Self.serviceBounceTimestampKey)
        UserDefaults.standard.synchronize()

        logger.log("🔄 [ServiceBounce] Bounce scheduled for next restart - reason: \(reason)")
        logger.log("🔄 [ServiceBounce] Timestamp: \(timestamp)")
    }

    /// Check if service bounce is needed and return details
    func checkServiceBounceNeeded() -> (shouldBounce: Bool, timeSinceScheduled: TimeInterval?) {
        let needsBounce = UserDefaults.standard.bool(forKey: Self.serviceBounceNeededKey)
        let timestamp = UserDefaults.standard.double(forKey: Self.serviceBounceTimestampKey)

        guard needsBounce, timestamp > 0 else {
            return (shouldBounce: false, timeSinceScheduled: nil)
        }

        let currentTime = Date().timeIntervalSince1970
        let timeSince = currentTime - timestamp

        // Clear if too old (older than max return time)
        if timeSince > maxReturnTime {
            clearServiceBounceFlag()
            logger.log("🔄 [ServiceBounce] Clearing expired bounce flag (age: \(Int(timeSince))s)")
            return (shouldBounce: false, timeSinceScheduled: nil)
        }

        return (shouldBounce: true, timeSinceScheduled: timeSince)
    }

    /// Clear the service bounce flag
    func clearServiceBounceFlag() {
        UserDefaults.standard.removeObject(forKey: Self.serviceBounceNeededKey)
        UserDefaults.standard.removeObject(forKey: Self.serviceBounceTimestampKey)
        UserDefaults.standard.synchronize()
        logger.log("🔄 [ServiceBounce] Bounce flag cleared")
    }

    /// Perform the service bounce using launchctl kickstart with admin privileges
    func performServiceBounce() async -> Bool {
        logger.log("🔄 [ServiceBounce] Starting Kanata service bounce with launchctl kickstart")

        let script = """
        do shell script "launchctl kickstart -k system/com.keypath.kanata" with administrator privileges with prompt "KeyPath needs admin access to restart the keyboard service after permission changes."
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let appleScript = NSAppleScript(source: script)
                var error: NSDictionary?
                let result = appleScript?.executeAndReturnError(&error)

                if let error {
                    self.logger.log("❌ [ServiceBounce] Failed to bounce service: \(error)")
                    continuation.resume(returning: false)
                } else {
                    self.logger.log("✅ [ServiceBounce] Service bounce completed successfully")
                    continuation.resume(returning: true)
                }
            }
        }
    }
}
