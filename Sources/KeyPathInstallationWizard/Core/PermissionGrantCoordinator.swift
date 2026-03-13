import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import Observation
import SwiftUI

public enum CoordinatorPermissionType: String, CaseIterable {
    case accessibility
    case inputMonitoring = "input_monitoring"

    public var displayName: String {
        switch self {
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        }
    }

    public var userDefaultsKey: String {
        "wizard_pending_\(rawValue)"
    }

    public var timestampKey: String {
        "wizard_\(rawValue)_timestamp"
    }
}

@MainActor
@Observable
public class PermissionGrantCoordinator {
    public static let shared = PermissionGrantCoordinator()

    @ObservationIgnored private let logger = AppLogger.shared
    @ObservationIgnored private let maxReturnTime: TimeInterval = 600 // 10 minutes

    /// Prevent double-dismiss race conditions
    @ObservationIgnored private var didFireCompletion = false

    // Service bounce flag keys
    @ObservationIgnored private static let serviceBounceNeededKey = "keypath_service_bounce_needed"
    @ObservationIgnored private static let serviceBounceTimestampKey = "keypath_service_bounce_timestamp"

    private init() {}

    public func initiatePermissionGrant(
        for permissionType: CoordinatorPermissionType,
        instructions: String,
        onComplete: (() -> Void)? = nil
    ) {
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

    private func showInstructionsDialog(
        for permissionType: CoordinatorPermissionType,
        instructions: String,
        onComplete: @escaping () -> Void
    ) {
        // Use inline wizard feedback instead of a modal alert.
        showUserFeedback(instructions)
        openSystemSettings(for: permissionType)
        onComplete()
    }

    private func openSystemSettings(for permissionType: CoordinatorPermissionType) {
        let settingsPath =
            switch permissionType {
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
        Task { @MainActor in
            _ = await WizardSleep.ms(500)
            NSApp.terminate(nil)
        }
    }

    public func checkForPendingPermissionGrant() -> (
        shouldRestart: Bool, permissionType: CoordinatorPermissionType?
    ) {
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

    public func performPermissionRestart(
        for permissionType: CoordinatorPermissionType,
        kanataManager: any RuntimeCoordinating,
        completion: @escaping (Bool) -> Void
    ) {
        let timestamp = UserDefaults.standard.double(forKey: permissionType.timestampKey)
        let originalDate = Date(timeIntervalSince1970: timestamp)
        let timeSince = Date().timeIntervalSince1970 - timestamp

        logger.log("PERMISSION RESTART CONTEXT:")
        logger.log("  - Original timestamp: \(timestamp) (\(originalDate))")
        logger.log("  - Time elapsed: \(String(format: "%.1f", timeSince))s  ")
        logger.log(
            "  - Assumption: User granted \(permissionType.displayName) permissions to KeyPath and/or kanata"
        )
        logger.log("  - Action: Restarting kanata process to pick up new permissions")
        logger.log("  - Method: RuntimeCoordinator retryAfterFix for complete restart")

        // Skip auto-launch to prevent resetting wizard flag
        logger.log("SKIPPING auto-launch (would reset wizard flag)")

        // Log pre-restart permissions snapshot
        logPermissionSnapshot()

        // Attempt restart
        logger.log("KANATA RESTART ATTEMPT:")
        let startTime = Date()

        // Provide immediate user feedback
        showUserFeedback(
            "🔄 Restarting keyboard service for new \(permissionType.displayName.lowercased()) permissions..."
        )

        Task {
            let success = await attemptKanataRestart(kanataManager: kanataManager)
            let duration = Date().timeIntervalSince1970 - startTime.timeIntervalSince1970

            if success {
                logger.log("  • Service restart success: true")
                logger.log("  • Duration: \(String(format: "%.2f", duration))s")

                // Show success feedback
                showUserFeedback(
                    "Keyboard service restarted - \(permissionType.displayName) permissions active!"
                )

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

    private func attemptKanataRestart(kanataManager: any RuntimeCoordinating) async -> Bool {
        let success = await kanataManager.restartKanata(
            reason: "Permission grant restart"
        )
        if success {
            await kanataManager.updateStatus()
        }
        return success
    }

    private func logPermissionSnapshot() {
        Task {
            logger.log("PRE-RESTART SNAPSHOT:")

            let snapshot = await PermissionOracle.shared.currentSnapshot()

            let keyPathAccessibility = snapshot.keyPath.accessibility.isReady
            let keyPathInputMonitoring = snapshot.keyPath.inputMonitoring.isReady

            logger.log("  KeyPath permissions:")
            logger.log("    • Accessibility: \(keyPathAccessibility ? "granted" : "denied")")
            logger.log("    • Input Monitoring: \(keyPathInputMonitoring ? "granted" : "denied")")

            logger.log("  Kanata permissions (source: \(snapshot.kanata.source)):")
            logger.log("    • Accessibility: \(snapshot.kanata.accessibility)")
            logger.log("    • Input Monitoring: \(snapshot.kanata.inputMonitoring)")

            logger.log("  System ready: \(snapshot.isSystemReady)")

            if !snapshot.isSystemReady, let issue = snapshot.blockingIssue {
                logger.log("  Blocking issue: \(issue)")
            }
        }
    }

    public func clearPendingFlag(for permissionType: CoordinatorPermissionType) {
        UserDefaults.standard.removeObject(forKey: permissionType.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: permissionType.timestampKey)
        UserDefaults.standard.synchronize()
    }

    public func clearAllPendingFlags() {
        for permissionType in CoordinatorPermissionType.allCases {
            clearPendingFlag(for: permissionType)
        }
    }

    private func showUserFeedback(_ message: String) {
        // Already on @MainActor; post notification directly
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowUserFeedback"),
            object: nil,
            userInfo: ["message": message]
        )
    }

    public func reopenWizard(for permissionType: CoordinatorPermissionType) {
        logger.log("REOPENING wizard - checking \(permissionType.displayName) permission status")

        // Check permissions asynchronously and set appropriate flags
        Task { @MainActor in
            let permissionsGranted = await checkIfPermissionsGranted(for: permissionType)

            if permissionsGranted {
                logger.log("✅ Permissions granted! Returning to Summary page")
                UserDefaults.standard.set(true, forKey: "wizard_return_to_summary")
            } else {
                logger.log("⚠️ Permissions still missing - returning to \(permissionType.displayName) page")
                // Set the appropriate wizard return flag
                switch permissionType {
                case .accessibility:
                    UserDefaults.standard.set(true, forKey: "wizard_return_to_accessibility")
                case .inputMonitoring:
                    UserDefaults.standard.set(true, forKey: "wizard_return_to_input_monitoring")
                }
            }

            logger.log("Posting .wizardOpenInstallationWizard notification")
            NotificationCenter.default.post(name: .wizardOpenInstallationWizard, object: nil)
            logger.log("  - Wizard shown")
        }
    }

    /// Check if permissions were successfully granted for the given permission type
    private func checkIfPermissionsGranted(for permissionType: CoordinatorPermissionType) async
        -> Bool
    {
        let snapshot = await PermissionOracle.shared.currentSnapshot()

        switch permissionType {
        case .accessibility:
            // Both KeyPath and kanata should have accessibility
            let keyPathGranted = snapshot.keyPath.accessibility == .granted
            let kanataGranted = snapshot.kanata.accessibility == .granted
            return keyPathGranted && kanataGranted

        case .inputMonitoring:
            // Both KeyPath and kanata should have input monitoring
            let keyPathGranted = snapshot.keyPath.inputMonitoring == .granted
            let kanataGranted = snapshot.kanata.inputMonitoring == .granted
            return keyPathGranted && kanataGranted
        }
    }

    // MARK: - Service Bounce Management

    /// Set flag to indicate Kanata service should be bounced on next app restart
    public func setServiceBounceNeeded(reason: String) {
        let timestamp = Date().timeIntervalSince1970
        UserDefaults.standard.set(true, forKey: Self.serviceBounceNeededKey)
        UserDefaults.standard.set(timestamp, forKey: Self.serviceBounceTimestampKey)
        UserDefaults.standard.synchronize()

        logger.log("🔄 [ServiceBounce] Bounce scheduled for next restart - reason: \(reason)")
        logger.log("🔄 [ServiceBounce] Timestamp: \(timestamp)")
    }

    /// Check if service bounce is needed and return details
    public func checkServiceBounceNeeded() -> (shouldBounce: Bool, timeSinceScheduled: TimeInterval?) {
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
    public func clearServiceBounceFlag() {
        UserDefaults.standard.removeObject(forKey: Self.serviceBounceNeededKey)
        UserDefaults.standard.removeObject(forKey: Self.serviceBounceTimestampKey)
        UserDefaults.standard.synchronize()
        logger.log("🔄 [ServiceBounce] Bounce flag cleared")
    }

    /// Perform the service bounce via the privileged coordinator seam.
    public func performServiceBounce() async -> Bool {
        logger.log("🔄 [ServiceBounce] Bounce via PrivilegeBroker.recoverRequiredRuntimeServices")
        do {
            try await PrivilegeBroker().recoverRequiredRuntimeServices()
            logger.log("✅ [ServiceBounce] Bounce completed successfully")
            return true
        } catch {
            logger.log("❌ [ServiceBounce] Bounce failed: \(error.localizedDescription)")
            return false
        }
    }
}
