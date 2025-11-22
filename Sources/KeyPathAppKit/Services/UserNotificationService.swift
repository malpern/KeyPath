import AppKit
import Foundation
import KeyPathCore
import KeyPathWizardCore
import UserNotifications

/// Manages local user notifications for KeyPath
@MainActor
final class UserNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UserNotificationService()

    private let center: UNUserNotificationCenter?
    private let preferences: PreferencesService
    private let authorizationRequestedKey = "KeyPath.NotificationAuthorizationRequested"
    private let lastSentKey = "KeyPath.Notifications.LastSent"

    // Simple in-memory cache to avoid repeated UserDefaults lookups in-session
    private var lastSentCache: [String: Date] = [:]

    // Category identifiers
    enum Category: String {
        case serviceFailure = "KP_SERVICE_FAILURE"
        case recovery = "KP_RECOVERY"
        case permission = "KP_PERMISSION"
        case info = "KP_INFO"
    }

    // Action identifiers
    enum Action: String {
        case openWizard = "KP_ACTION_OPEN_WIZARD"
        case retryStart = "KP_ACTION_RETRY_START"
        case openInputMonitoring = "KP_ACTION_OPEN_INPUT_MONITORING"
        case openAccessibility = "KP_ACTION_OPEN_ACCESSIBILITY"
        case openApp = "KP_ACTION_OPEN_APP"
    }

    private init(preferences: PreferencesService = .shared) {
        self.preferences = preferences

        // Skip notification center initialization in test environment
        if TestEnvironment.isRunningTests {
            center = nil
            super.init()
            AppLogger.shared.debug(
                "🧪 [UserNotificationService] Initialized in test mode - notifications disabled")
            return
        }

        center = UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
        registerCategories()
        loadLastSentCache()
    }

    /// Request authorization if it hasn't been requested before
    func requestAuthorizationIfNeeded() {
        guard let center else { return }
        let requested = UserDefaults.standard.bool(forKey: authorizationRequestedKey)
        guard !requested else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            UserDefaults.standard.set(true, forKey: self.authorizationRequestedKey)
            Task { @MainActor in
                self.preferences.notificationsEnabled = granted
            }
        }
    }

    // MARK: - Category Registration

    private func registerCategories() {
        guard let center else { return }

        let openWizard = UNNotificationAction(
            identifier: Action.openWizard.rawValue, title: "Open Wizard", options: [.foreground]
        )
        let retryStart = UNNotificationAction(
            identifier: Action.retryStart.rawValue, title: "Start Service", options: []
        )
        let openIM = UNNotificationAction(
            identifier: Action.openInputMonitoring.rawValue, title: "Open Input Monitoring",
            options: [.foreground]
        )
        let openAX = UNNotificationAction(
            identifier: Action.openAccessibility.rawValue, title: "Open Accessibility",
            options: [.foreground]
        )
        let openApp = UNNotificationAction(
            identifier: Action.openApp.rawValue, title: "Open KeyPath", options: [.foreground]
        )

        let serviceFailure = UNNotificationCategory(
            identifier: Category.serviceFailure.rawValue,
            actions: [retryStart, openWizard], intentIdentifiers: [], options: []
        )
        let recovery = UNNotificationCategory(
            identifier: Category.recovery.rawValue,
            actions: [openApp], intentIdentifiers: [], options: []
        )
        let permission = UNNotificationCategory(
            identifier: Category.permission.rawValue,
            actions: [openIM, openAX, openWizard], intentIdentifiers: [], options: []
        )
        let info = UNNotificationCategory(
            identifier: Category.info.rawValue,
            actions: [openApp], intentIdentifiers: [], options: []
        )

        center.setNotificationCategories([serviceFailure, recovery, permission, info])
    }

    // MARK: - Dedupe / Rate limiting

    private func loadLastSentCache() {
        if let dict = UserDefaults.standard.dictionary(forKey: lastSentKey) as? [String: TimeInterval] {
            var cache: [String: Date] = [:]
            for (k, ts) in dict {
                cache[k] = Date(timeIntervalSince1970: ts)
            }
            lastSentCache = cache
        }
    }

    private func saveLastSentCache() {
        var dict: [String: TimeInterval] = [:]
        for (k, d) in lastSentCache {
            dict[k] = d.timeIntervalSince1970
        }
        UserDefaults.standard.set(dict, forKey: lastSentKey)
    }

    private func shouldSend(key: String, ttl: TimeInterval) -> Bool {
        if let last = lastSentCache[key], Date().timeIntervalSince(last) < ttl {
            return false
        }
        lastSentCache[key] = Date()
        saveLastSentCache()
        return true
    }

    private func isFrontmost() -> Bool {
        // If app is active and has key window, prefer in-app UI
        if let app = NSApplication.shared as NSApplication? {
            return app.isActive
        }
        return false
    }

    /// Send a notification if enabled, not frontmost (unless override), and not rate-limited.
    private func sendNotification(
        title: String, body: String, category: Category, key: String, ttl: TimeInterval,
        allowWhenFrontmost: Bool = false
    ) {
        guard let center else { return }
        guard preferences.notificationsEnabled else { return }
        if !allowWhenFrontmost, isFrontmost() { return }
        guard shouldSend(key: key, ttl: ttl) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        center.add(request)
    }

    /// Notify user of a launch failure
    func notifyLaunchFailure(_ status: LaunchFailureStatus) {
        let body = status.shortMessage
        sendNotification(
            title: "Kanata Launch Failed",
            body: body,
            category: .serviceFailure,
            key: "service.failure.\(body)",
            ttl: 120
        )
    }

    // notifyStatusChange removed - SimpleKanataState is deprecated

    // MARK: - Additional Notification Helpers

    func notifyPermissionRequired(_ missing: [PermissionRequirement]) {
        guard !missing.isEmpty else { return }
        let names = missing.map { req -> String in
            switch req {
            case .kanataInputMonitoring, .keyPathInputMonitoring: return "Input Monitoring"
            case .kanataAccessibility, .keyPathAccessibility: return "Accessibility"
            case .driverExtensionEnabled: return "Driver Extension"
            case .backgroundServicesEnabled: return "Background Services"
            }
        }
        let summary = Array(Set(names)).joined(separator: ", ")
        sendNotification(
            title: "Permission Required",
            body: "Grant: \(summary)",
            category: .permission,
            key: "perm.\(summary)",
            ttl: 1800
        )
    }

    func notifyRecoverySucceeded(_ message: String = "All set") {
        sendNotification(
            title: "KeyPath Ready",
            body: message,
            category: .recovery,
            key: "recovery.success",
            ttl: 600
        )
    }

    func notifyConfigEvent(_ title: String, body: String, key: String) {
        sendNotification(
            title: title,
            body: body,
            category: .info,
            key: key,
            ttl: 1800,
            allowWhenFrontmost: false
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        switch action {
        case Action.openWizard.rawValue:
            NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
        case Action.retryStart.rawValue:
            NotificationCenter.default.post(name: .retryStartService, object: nil)
        case Action.openInputMonitoring.rawValue:
            NotificationCenter.default.post(name: .openInputMonitoringSettings, object: nil)
        case Action.openAccessibility.rawValue:
            NotificationCenter.default.post(name: .openAccessibilitySettings, object: nil)
        case Action.openApp.rawValue:
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        default:
            break
        }
        completionHandler()
    }
}
