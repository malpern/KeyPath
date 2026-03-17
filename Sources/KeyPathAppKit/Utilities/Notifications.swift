import Foundation

extension Notification.Name {
    // Startup coordination
    static let kp_startupWarm = Notification.Name("KeyPath.Startup.Warm")
    static let kp_startupValidate = Notification.Name("KeyPath.Startup.Validate")
    static let kp_startupAutoLaunch = Notification.Name("KeyPath.Startup.AutoLaunch")
    static let kp_startupEmergencyMonitor = Notification.Name("KeyPath.Startup.EmergencyMonitor")
    static let kp_startupRevalidate = Notification.Name("KeyPath.Startup.Revalidate")

    // Wizard events
    static let showWizard = Notification.Name("ShowWizard")
    static let wizardClosed = Notification.Name("KeyPath.Wizard.Closed")

    // Settings navigation
    static let openSettingsGeneral = Notification.Name("KeyPath.Settings.General")
    static let openSettingsStatus = Notification.Name("KeyPath.Settings.Status")
    static let openSettingsRules = Notification.Name("KeyPath.Settings.Rules")
    static let openSettingsSimulator = Notification.Name("KeyPath.Settings.Simulator")
    static let openSettingsSystemStatus = Notification.Name("KeyPath.Settings.SystemStatus")
    static let openSettingsLogs = Notification.Name("KeyPath.Settings.Logs")
    static let openSettingsAdvanced = Notification.Name("KeyPath.Settings.Advanced")

    // User notification actions
    static let openInstallationWizard = Notification.Name("KeyPath.Action.OpenWizard")
    static let retryStartService = Notification.Name("KeyPath.Action.RetryStart")
    static let openInputMonitoringSettings = Notification.Name("KeyPath.Action.OpenInputMonitoring")
    static let openAccessibilitySettings = Notification.Name("KeyPath.Action.OpenAccessibility")
    static let openApp = Notification.Name("KeyPath.Action.OpenApp")
    static let resetToSafeConfig = Notification.Name("KeyPath.Action.ResetToSafeConfig")

    /// SMAppService
    static let smAppServiceApprovalRequired = Notification.Name(
        "KeyPath.SMAppService.ApprovalRequired"
    )

    /// Kanata service health
    static let kanataCrashLoopDetected = Notification.Name("KeyPath.Kanata.CrashLoopDetected")
    static let splitRuntimeHostExited = Notification.Name("KeyPath.SplitRuntime.HostExited")
    static let exerciseCoordinatorSplitRuntimeRecovery = Notification.Name("KeyPath.SplitRuntime.ExerciseCoordinatorRecovery")
    static let exerciseCoordinatorSplitRuntimeRestartSoak = Notification.Name("KeyPath.SplitRuntime.ExerciseCoordinatorRestartSoak")

    /// Rule collections
    static let ruleCollectionsChanged = Notification.Name("KeyPath.RuleCollections.Changed")

    /// Config validation
    static let configValidationFailed = Notification.Name("KeyPath.Config.ValidationFailed")
    static let configReloadFailed = Notification.Name("KeyPath.Config.ReloadFailed")
    static let configReloadRecovered = Notification.Name("KeyPath.Config.ReloadRecovered")

    /// Mapper drawer
    /// Posted when a key is clicked and should be selected in the mapper drawer
    /// userInfo: keyCode (UInt16), inputKey (String), outputKey (String), optional shiftedOutputKey (String), layer (String)
    static let mapperDrawerKeySelected = Notification.Name("KeyPath.Mapper.DrawerKeySelected")

    /// Uninstall flow
    static let keyPathUninstallCompleted = Notification.Name("KeyPath.Uninstall.Completed")

    /// Diagnostics
    static let verboseLoggingChanged = Notification.Name("KeyPath.Diagnostics.VerboseLoggingChanged")

    /// Config-affecting preference changed (e.g., nav trigger mode) - triggers config regeneration
    static let configAffectingPreferenceChanged = Notification.Name("KeyPath.Preferences.ConfigAffectingChanged")

    /// Device selection changed (user toggled keyboards in Devices tab) - triggers config regeneration
    static let deviceSelectionChanged = Notification.Name("KeyPath.Devices.SelectionChanged")
    /// Device selection apply completed. userInfo["success"] = Bool
    static let deviceSelectionApplyCompleted = Notification.Name("KeyPath.Devices.ApplyCompleted")

    /// HID keyboard connected (posted by HIDDeviceMonitor). object = HIDKeyboardEvent
    static let hidKeyboardConnected = Notification.Name("KeyPath.HID.KeyboardConnected")
    /// HID keyboard disconnected (posted by HIDDeviceMonitor). object = HIDKeyboardEvent
    static let hidKeyboardDisconnected = Notification.Name("KeyPath.HID.KeyboardDisconnected")
}
