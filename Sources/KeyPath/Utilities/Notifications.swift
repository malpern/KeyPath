import Foundation

extension Notification.Name {
    // Startup coordination
    static let kp_startupWarm = Notification.Name("KeyPath.Startup.Warm")
    static let kp_startupValidate = Notification.Name("KeyPath.Startup.Validate")
    static let kp_startupAutoLaunch = Notification.Name("KeyPath.Startup.AutoLaunch")
    static let kp_startupEmergencyMonitor = Notification.Name("KeyPath.Startup.EmergencyMonitor")
}

