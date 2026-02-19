import Foundation

/// Local preferences for KeyPath Insights, separate from the core KeyPath app.
@MainActor
enum InsightsPreferences {
    private enum Keys {
        static let activityLoggingEnabled = "KeyPathInsights.ActivityLogging.Enabled"
        static let activityLoggingConsentDate = "KeyPathInsights.ActivityLogging.ConsentDate"
    }

    static var activityLoggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.activityLoggingEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.activityLoggingEnabled)
            NotificationCenter.default.post(name: .insightsActivityLoggingChanged, object: nil)
        }
    }

    static var activityLoggingConsentDate: Date? {
        get {
            guard let timestamp = UserDefaults.standard.object(forKey: Keys.activityLoggingConsentDate) as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.activityLoggingConsentDate)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.activityLoggingConsentDate)
            }
        }
    }
}

extension Notification.Name {
    static let insightsActivityLoggingChanged = Notification.Name("KeyPathInsights.ActivityLogging.Changed")
}
