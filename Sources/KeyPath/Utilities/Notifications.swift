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

    // Settings navigation
    static let openSettingsGeneral = Notification.Name("KeyPath.Settings.General")
    static let openSettingsStatus = Notification.Name("KeyPath.Settings.Status")
    static let openSettingsRules = Notification.Name("KeyPath.Settings.Rules")
    static let openSettingsSystemStatus = Notification.Name("KeyPath.Settings.SystemStatus")
    static let openSettingsLogs = Notification.Name("KeyPath.Settings.Logs")
    static let openSettingsAdvanced = Notification.Name("KeyPath.Settings.Advanced")

    // User notification actions
    static let openInstallationWizard = Notification.Name("KeyPath.Action.OpenWizard")
    static let retryStartService = Notification.Name("KeyPath.Action.RetryStart")
    static let openInputMonitoringSettings = Notification.Name("KeyPath.Action.OpenInputMonitoring")
    static let openAccessibilitySettings = Notification.Name("KeyPath.Action.OpenAccessibility")
    static let openApp = Notification.Name("KeyPath.Action.OpenApp")
    static let pauseForLowPower = Notification.Name("KeyPath.Action.PauseLowPower")

    // SMAppService
    static let smAppServiceApprovalRequired = Notification.Name("KeyPath.SMAppService.ApprovalRequired")

    // Uninstall flow
    static let keyPathUninstallCompleted = Notification.Name("KeyPath.Uninstall.Completed")

    // Diagnostics
    static let verboseLoggingChanged = Notification.Name("KeyPath.Diagnostics.VerboseLoggingChanged")
}
