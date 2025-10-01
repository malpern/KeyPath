import Foundation

extension Notification.Name {
    // Startup coordination
    static let kp_startupWarm = Notification.Name("KeyPath.Startup.Warm")
    static let kp_startupValidate = Notification.Name("KeyPath.Startup.Validate")
    static let kp_startupAutoLaunch = Notification.Name("KeyPath.Startup.AutoLaunch")
    static let kp_startupEmergencyMonitor = Notification.Name("KeyPath.Startup.EmergencyMonitor")
    static let kp_startupRevalidate = Notification.Name("KeyPath.Startup.Revalidate")

    // Wizard events
    static let wizardClosed = Notification.Name("KeyPath.Wizard.Closed")

    // User notification actions
    static let openInstallationWizard = Notification.Name("KeyPath.Action.OpenWizard")
    static let retryStartService = Notification.Name("KeyPath.Action.RetryStart")
    static let openInputMonitoringSettings = Notification.Name("KeyPath.Action.OpenInputMonitoring")
    static let openAccessibilitySettings = Notification.Name("KeyPath.Action.OpenAccessibility")
    static let openApp = Notification.Name("KeyPath.Action.OpenApp")
}
