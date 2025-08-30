import Foundation
import UserNotifications

/// Manages local user notifications for KeyPath
@MainActor
final class UserNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UserNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let preferences: PreferencesService
    private let authorizationRequestedKey = "KeyPath.NotificationAuthorizationRequested"

    private override init(preferences: PreferencesService = .shared) {
        self.preferences = preferences
        super.init()
        center.delegate = self
    }

    /// Request authorization if it hasn't been requested before
    func requestAuthorizationIfNeeded() {
        let requested = UserDefaults.standard.bool(forKey: authorizationRequestedKey)
        guard !requested else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            UserDefaults.standard.set(true, forKey: self.authorizationRequestedKey)
            Task { @MainActor in
                self.preferences.notificationsEnabled = granted
            }
        }
    }

    /// Send a generic notification if the user has enabled notifications
    private func sendNotification(title: String, body: String) {
        guard preferences.notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    /// Notify user of a launch failure
    func notifyLaunchFailure(_ status: LaunchFailureStatus) {
        sendNotification(title: "Kanata Launch Failed", body: status.shortMessage)
    }

    /// Notify user of a status change
    func notifyStatusChange(_ state: SimpleKanataState) {
        sendNotification(title: "Kanata Status", body: "Kanata is now \(state.displayName)")
    }
}

